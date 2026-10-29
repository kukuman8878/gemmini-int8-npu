# tb/tb_fifo.py : fifo (valid/ready) 的 cocotb 测试
#   覆盖: 复位/填充排空/满拒写/空拒读/同时读写/指针回绕/随机握手 scoreboard
import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.wr_valid.value = 0
    dut.rd_ready.value = 0
    dut.wr_data.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def edge(dut):
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def write_one(dut, data):
    """阻塞式写一个数据 (沿前采样 wr_ready, 满时等待)"""
    while True:
        dut.wr_valid.value = 1
        dut.wr_data.value = data
        await Timer(1, unit="step")
        ready = int(dut.wr_ready.value)      # 沿前采样
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
        if ready:
            dut.wr_valid.value = 0
            return


async def read_one(dut):
    """阻塞式读一个数据 (沿前采样 rd_data), 返回读到的值"""
    while True:
        dut.rd_ready.value = 1
        await Timer(1, unit="step")
        if int(dut.rd_valid.value):
            data = int(dut.rd_data.value)    # 沿前采样组合输出
            await RisingEdge(dut.clk)
            await Timer(1, unit="step")
            dut.rd_ready.value = 0
            return data
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")


@cocotb.test()
async def test_reset(dut):
    """复位后空, rd_valid=0"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    assert int(dut.empty.value) == 1, "empty after reset"
    assert int(dut.full.value) == 0, "not full after reset"
    assert int(dut.rd_valid.value) == 0, "no read data after reset"
    assert int(dut.wr_ready.value) == 1, "writable after reset"


@cocotb.test()
async def test_fill_drain(dut):
    """写满 16 再读空 16, 顺序正确"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for i in range(16):
        await write_one(dut, 0xA0 + i)
    assert int(dut.full.value) == 1, "full after 16 writes"
    assert int(dut.wr_ready.value) == 0, "wr_ready=0 when full"

    for i in range(16):
        got = await read_one(dut)
        assert got == 0xA0 + i, f"read {i}: got {got:#x}, expect {0xA0 + i:#x}"
    assert int(dut.empty.value) == 1, "empty after 16 reads"


@cocotb.test()
async def test_overflow_reject(dut):
    """满时 wr_valid=1 不被接受 (wr_ready=0), 数据不丢失"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for i in range(16):
        await write_one(dut, 0x10 + i)
    # 满时再发一拍写
    dut.wr_valid.value = 1
    dut.wr_data.value = 0xFF
    await edge(dut)
    assert int(dut.wr_ready.value) == 0, "wr_ready=0 when full"
    dut.wr_valid.value = 0
    await edge(dut)
    assert int(dut.full.value) == 1, "still full (rejected write)"


@cocotb.test()
async def test_underflow_reject(dut):
    """空时 rd_ready=1 无数据 (rd_valid=0), 指针不动"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    dut.rd_ready.value = 1
    for _ in range(3):
        assert int(dut.rd_valid.value) == 0, "rd_valid=0 when empty"
        await edge(dut)
    dut.rd_ready.value = 0
    assert int(dut.empty.value) == 1, "still empty (rejected reads)"


@cocotb.test()
async def test_simult_rw(dut):
    """同时读写 8 拍: cnt 不变, 数据不丢不乱"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for i in range(8):
        await write_one(dut, 0x10 + i)
    assert not int(dut.full.value) and not int(dut.empty.value)

    for i in range(8):
        dut.wr_valid.value = 1
        dut.rd_ready.value = 1
        dut.wr_data.value = 0x20 + i
        await Timer(1, unit="step")
        assert int(dut.rd_data.value) == 0x10 + i, \
            f"simul-rw {i}: got {int(dut.rd_data.value):#x}, expect {0x10 + i:#x}"
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
    dut.wr_valid.value = 0
    dut.rd_ready.value = 0
    await Timer(1, unit="step")
    assert not int(dut.full.value) and not int(dut.empty.value), "cnt unchanged"

    for i in range(8):
        got = await read_one(dut)
        assert got == 0x20 + i, f"drain {i}: got {got:#x}, expect {0x20 + i:#x}"
    assert int(dut.empty.value) == 1


@cocotb.test()
async def test_pointer_wrap(dut):
    """写12->读12->写8: 指针跨 15->0 边界, 数据不丢"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for i in range(12):
        await write_one(dut, 0x40 + i)
    for i in range(12):
        got = await read_one(dut)
        assert got == 0x40 + i, f"read {i}: got {got:#x}"
    assert int(dut.empty.value) == 1

    for i in range(8):
        await write_one(dut, 0x80 + i)
    for i in range(8):
        got = await read_one(dut)
        assert got == 0x80 + i, f"wrap-read {i}: got {got:#x}"
    assert int(dut.empty.value) == 1


@cocotb.test()
async def test_random_handshake(dut):
    """随机握手 2000 拍: 随机 wr_valid/rd_ready, Python deque 参考模型逐拍比对"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    random.seed(2026)
    model = deque()
    wr_seq = 0
    fails = 0
    cycles = 2000

    for cycle in range(cycles):
        # 占用率交叉校验: 模型长度与 DUT full/empty 必须一致
        # (可捕获 wr_ready/rd_valid 输出错误而内部计数正确的缺陷)
        if (len(model) == 0) != bool(int(dut.empty.value)):
            fails += 1
            dut._log.error("cycle %d: empty flag %d vs model len %d",
                           cycle, int(dut.empty.value), len(model))
        if (len(model) == 16) != bool(int(dut.full.value)):
            fails += 1
            dut._log.error("cycle %d: full flag %d vs model len %d",
                           cycle, int(dut.full.value), len(model))

        wv = random.choice([0, 1, 1, 1])   # push 偏多: 稳态趋满, 覆盖满态边界
        rr = random.choice([0, 0, 1])      # pop 偏少
        data = 0
        if wv:
            data = wr_seq & 0xFF
            wr_seq += 1
        dut.wr_valid.value = wv
        dut.rd_ready.value = rr
        dut.wr_data.value = data

        await Timer(1, unit="step")
        wr_ready_pre = int(dut.wr_ready.value)   # 沿前状态
        rd_valid_pre = int(dut.rd_valid.value)
        empty_pre = int(dut.empty.value)
        full_pre = int(dut.full.value)
        push = wv and wr_ready_pre
        pop = rr and rd_valid_pre

        # 正确协议下: push 必然 !full (wr_ready 门控), pop 必然 !empty (rd_valid 门控)
        # 若推得握手发生但标志矛盾, 说明 ready/valid 输出被破坏
        if push and full_pre:
            fails += 1
            dut._log.error("cycle %d: push inferred but full flag set", cycle)
        if pop and empty_pre:
            fails += 1
            dut._log.error("cycle %d: pop inferred but empty flag set", cycle)

        if pop:
            if len(model) == 0:
                fails += 1
                dut._log.error("cycle %d: pop from empty model", cycle)
            else:
                want = model.popleft()
                got = int(dut.rd_data.value)
                if got != want:
                    fails += 1
                    dut._log.error("cycle %d: got %#x want %#x", cycle, got, want)

        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
        if push:
            model.append(data)

        if fails >= 5:
            break

    dut._log.info("random handshake done: %d cycles", cycles)
    assert fails == 0, f"{fails} mismatches"
