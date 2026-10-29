# tb/tb_top.py : npu_top 端到端测试 (W6 门禁: P0 核心功能)
#   覆盖: 基本 tile / K 随机 (含 K>N) / 输入暂停 / 输出反压 / 连续任务清零 / 中途复位 / 非法配置 / done 单拍
#   Driver/Monitor 助手见 tb_common.py, Scoreboard 见 verification/scoreboard.py
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock

from golden_model import matmul_ref
from tb_common import (N, cfg_task, compare, edge, rand_mat_k, reset_dut,
                       run_task, start_task)


@cocotb.test()
async def test_e2e_basic(dut):
    """黄金向量 tile: K=2 (零填充), 端到端握手 + done 单拍"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    K = 2
    A = [[1, 2], [3, 4], [0, 0], [0, 0]]
    B = [[5, 6, 0, 0], [7, 8, 0, 0]]
    got = await run_task(dut, A, B, K)
    want = matmul_ref(A, B)
    assert compare(dut, got, want, "e2e-basic") == 0

    # done: 握手沿后单拍
    assert int(dut.done.value) == 1, "done pulse after handshake"
    await edge(dut)
    assert int(dut.done.value) == 0, "done single cycle"
    assert int(dut.busy.value) == 0, "busy deasserted"
    dut._log.info("e2e basic tile passed")


@cocotb.test()
async def test_e2e_random_k(dut):
    """K ∈ {1,2,4,8,16} 随机 tile (含 K>N)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for K in (1, 2, 4, 8, 16):
        A = rand_mat_k(N, K, 110 + K)
        B = rand_mat_k(K, N, 120 + K)
        got = await run_task(dut, A, B, K)
        fails = compare(dut, got, matmul_ref(A, B), f"e2e-K={K}")
        assert fails == 0, f"{fails} mismatches for K={K}"
    dut._log.info("e2e random K done")


@cocotb.test()
async def test_e2e_input_pause(dut):
    """输入暂停: LOAD 中途 in_valid=0 不影响结果"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    K = 4
    A = rand_mat_k(N, K, 131)
    B = rand_mat_k(K, N, 132)
    got = await run_task(dut, A, B, K, pauses=(1, 3))
    assert compare(dut, got, matmul_ref(A, B), "e2e-pause") == 0
    dut._log.info("e2e input pause passed")


@cocotb.test()
async def test_e2e_backpressure(dut):
    """输出反压: out_ready=0 期间 out_valid 保持、数据稳定"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    K = 4
    A = rand_mat_k(N, K, 141)
    B = rand_mat_k(K, N, 142)
    got = await run_task(dut, A, B, K, hold_ready=4)
    assert compare(dut, got, matmul_ref(A, B), "e2e-backpressure") == 0
    dut._log.info("e2e output backpressure passed")


@cocotb.test()
async def test_e2e_back_to_back(dut):
    """连续任务: 第二任务结果只含 C2 (任务边界清零, 无旧状态泄漏)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A1, B1 = rand_mat_k(N, 4, 151), rand_mat_k(4, N, 152)
    A2, B2 = rand_mat_k(N, 2, 153), rand_mat_k(2, N, 154)
    got1 = await run_task(dut, A1, B1, 4)
    assert compare(dut, got1, matmul_ref(A1, B1), "e2e-b2b-1") == 0
    got2 = await run_task(dut, A2, B2, 2)
    assert compare(dut, got2, matmul_ref(A2, B2), "e2e-b2b-2") == 0
    dut._log.info("e2e back-to-back (per-task clear) passed")


@cocotb.test()
async def test_e2e_mid_reset(dut):
    """任务中途复位: busy 清除回 IDLE, 之后新任务正确"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    K = 4
    A1, B1 = rand_mat_k(N, K, 161), rand_mat_k(K, N, 162)
    await cfg_task(dut, K)
    await start_task(dut)
    for k in range(2):                       # 只呈现 2 拍
        for i in range(N):
            dut.a_vec[i].value = A1[i][k]
        for j in range(N):
            dut.b_vec[j].value = B1[k][j]
        dut.in_valid.value = 1
        await edge(dut)
    dut.in_valid.value = 0

    await reset_dut(dut)                     # 中途复位
    assert int(dut.busy.value) == 0

    A2, B2 = rand_mat_k(N, 3, 163), rand_mat_k(3, N, 164)
    got = await run_task(dut, A2, B2, 3)
    assert compare(dut, got, matmul_ref(A2, B2), "e2e-mid-reset") == 0
    dut._log.info("e2e mid-task reset passed")


@cocotb.test()
async def test_e2e_illegal_and_stale(dut):
    """非法 K 拒绝; 任务完成后旧配置失效 (需重新 cfg)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 非法 K=0
    dut.cfg_k.value = 0
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.busy.value) == 0, "illegal K=0 must not start"

    # 合法任务
    A, B = rand_mat_k(N, 2, 171), rand_mat_k(2, N, 172)
    got = await run_task(dut, A, B, 2)
    assert compare(dut, got, matmul_ref(A, B), "e2e-stale-1") == 0

    # 完成后直接 start (旧配置应已失效)
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.busy.value) == 0, "stale config must not allow restart"
    dut._log.info("e2e illegal cfg + stale config passed")
