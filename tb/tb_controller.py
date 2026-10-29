# tb/tb_controller.py : controller FSM 全语义测试
#   覆盖: 复位/配置握手/非法配置/start 时序/LOAD 计数/输入暂停/排空/输出握手/done 单拍/busy 拒绝
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

N = 4


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.cfg_valid.value = 0
    dut.cfg_k.value = 0
    dut.start.value = 0
    dut.in_valid.value = 0
    dut.out_ready.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def edge(dut):
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


def state_str(s):
    return ["IDLE", "LOAD", "DRAIN", "OUT"][int(s)]


@cocotb.test()
async def test_reset_idle(dut):
    """复位后处于 IDLE, busy=0, cfg_ready=1"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    assert int(dut.state.value) == 0, "state should be IDLE after reset"
    assert int(dut.busy.value) == 0
    assert int(dut.cfg_ready.value) == 1, "cfg_ready should be 1 in IDLE"


@cocotb.test()
async def test_cfg_handshake(dut):
    """IDLE 下 cfg 握手生效; 可重复配置 (覆盖旧值)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_k.value = 64
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    assert int(dut.state.value) == 0, "still IDLE after cfg"
    assert int(dut.cfg_ready.value) == 1, "cfg_ready stays 1 in IDLE"

    # 第二次配置覆盖
    dut.cfg_k.value = 3
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut._log.info("cfg handshake ok (reconfig allowed)")


@cocotb.test()
async def test_illegal_cfg(dut):
    """非法 K (0 / >256) 被拒绝: start 不生效, 保持 IDLE (V11)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for bad_k in (0, 257, 511):
        dut.cfg_k.value = bad_k
        dut.cfg_valid.value = 1
        await edge(dut)
        dut.cfg_valid.value = 0
        dut.start.value = 1
        await edge(dut)
        dut.start.value = 0
        assert int(dut.state.value) == 0, f"illegal K={bad_k} must not start"
        assert int(dut.busy.value) == 0, f"busy should stay 0 for K={bad_k}"
    dut._log.info("illegal cfg rejected (K=0/257/511)")


@cocotb.test()
async def test_start_flow(dut):
    """cfg 后 start: busy=1, 进入 LOAD, in_ready=1; 同拍 cfg+start 不生效"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 同拍 cfg + start: start 必须无效 (cfg_done 尚未置位)
    dut.cfg_k.value = 4
    dut.cfg_valid.value = 1
    dut.start.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 0
    assert int(dut.state.value) == 0, "same-cycle cfg+start must not start"

    # 下一拍 start
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.state.value) == 1, "state should be LOAD after start"
    assert int(dut.busy.value) == 1, "busy=1 after start"
    assert int(dut.in_ready.value) == 1, "in_ready=1 in LOAD"
    assert int(dut.cfg_ready.value) == 0, "cfg_ready=0 while busy"
    dut._log.info("start flow ok")


@cocotb.test()
async def test_reconfig_same_cycle(dut):
    """已配置(IDLE)时同拍 cfg+start: start 无效, cfg 接收; 下拍 start 用新 K (决策6角落)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 先配置 K=4 (不启动)
    dut.cfg_k.value = 4
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    assert int(dut.state.value) == 0

    # 已配置状态下同拍 cfg(K=2) + start -> start 必须无效
    dut.cfg_k.value = 2
    dut.cfg_valid.value = 1
    dut.start.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 0
    assert int(dut.state.value) == 0, "same-cycle reconfig+start must not start"

    # 下拍 start -> 用新 K=2: 2 拍接受后进入 DRAIN
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.state.value) == 1
    for _ in range(2):
        dut.in_valid.value = 1
        await edge(dut)
    dut.in_valid.value = 0
    assert int(dut.state.value) == 2, "DRAIN after 2 accepts (new K=2 effective)"
    dut._log.info("reconfig same-cycle corner ok")


@cocotb.test()
async def test_load_stall_and_drain(dut):
    """LOAD 计数只在握手拍前进 (输入暂停不推进); K 拍后进入 DRAIN 恰好 2N-1 拍"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    K = 4
    dut.cfg_k.value = K
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0

    # LOAD: 接受 K 拍, 中间插入 2 拍 in_valid=0 (输入暂停)
    accepted = 0
    cycle = 0
    while accepted < K:
        dut.in_valid.value = 0 if cycle in (1, 3) else 1
        await Timer(1, unit="step")
        if int(dut.in_accept.value):          # 沿前采样握手
            accepted += 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
        if accepted < K:
            assert int(dut.state.value) == 1, f"still LOAD at accepted={accepted}"
        cycle += 1
    assert int(dut.state.value) == 2, "state should be DRAIN after K accepts"

    # DRAIN: 恰好 2N-1 拍后进入 OUT
    for _ in range(2 * N - 1):
        assert int(dut.state.value) == 2, "state should stay DRAIN"
        await edge(dut)
    assert int(dut.state.value) == 3, "state should be OUT after 2N-1 drain cycles"
    assert int(dut.out_valid.value) == 1, "out_valid=1 in OUT"
    dut._log.info("load stall + drain timing ok")


@cocotb.test()
async def test_output_handshake(dut):
    """OUTPUT: out_valid 保持等待 out_ready; done 单拍脉冲; 回 IDLE 且需重新配置"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    K = 1
    dut.cfg_k.value = K
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0

    dut.in_valid.value = 1
    await edge(dut)                      # 接受第 1 拍 -> DRAIN
    dut.in_valid.value = 0
    for _ in range(2 * N - 1):
        await edge(dut)
    assert int(dut.state.value) == 3

    # out_ready=0 时 out_valid 保持, done 不置位
    for _ in range(3):
        assert int(dut.out_valid.value) == 1, "out_valid must hold without out_ready"
        assert int(dut.done.value) == 0, "done must not pulse without out_ready"
        await edge(dut)

    # 握手: done 单拍脉冲
    dut.out_ready.value = 1
    await edge(dut)
    assert int(dut.done.value) == 1, "done pulse on handshake"
    dut.out_ready.value = 0
    await edge(dut)
    assert int(dut.done.value) == 0, "done is single-cycle"
    assert int(dut.state.value) == 0, "back to IDLE"
    assert int(dut.busy.value) == 0, "busy=0 after done"

    # 任务完成后旧配置已清: 直接 start 无效
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.state.value) == 0, "stale config must not allow restart"
    dut._log.info("output handshake + done pulse ok")


@cocotb.test()
async def test_busy_reject(dut):
    """busy 期间 cfg_valid=1 被拒绝 (cfg_ready=0), start 被忽略"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.cfg_k.value = 8
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.state.value) == 1, "LOAD after start"

    # busy 中 cfg + start
    dut.cfg_k.value = 2
    dut.cfg_valid.value = 1
    dut.start.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 0
    assert int(dut.cfg_ready.value) == 0, "cfg_ready=0 while busy"
    assert int(dut.state.value) == 1, "start ignored while busy"

    # 正常完成任务后回到 IDLE, 旧配置已清
    for _ in range(8):
        dut.in_valid.value = 1
        await edge(dut)
    dut.in_valid.value = 0
    for _ in range(2 * N - 1):
        await edge(dut)
    assert int(dut.state.value) == 3
    dut.out_ready.value = 1
    await edge(dut)
    dut.out_ready.value = 0
    assert int(dut.state.value) == 0, "back to IDLE after full task"
    dut._log.info("busy reject ok")
