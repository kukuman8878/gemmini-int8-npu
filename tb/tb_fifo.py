# sim/tb_sync_fifo.py : sync_fifo 的 cocotb 测试
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def reset_dut(dut):
    """复位 DUT: rst_n 拉低 2 个周期, 再放开"""
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_reset(dut):
    """测试1: 先写 3 个数据, 按复位后 FIFO 应被清空"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0

    await reset_dut(dut)

    # 写 3 个数据
    dut.wr_en.value = 1
    for i in range(3):
        dut.wr_data.value = 0xA0 + i
        await RisingEdge(dut.clk)
    dut.wr_en.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")

    assert dut.empty.value == 0, "write 3: empty should be 0"

    # 按复位
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(1, unit="step")

    assert dut.empty.value == 1, "reset: empty should be 1"
    assert dut.full.value == 0, "reset: full should be 0"


@cocotb.test()
async def test_write_full(dut):
    """测试2: 连写 9 个, 前 8 个进, full=1, 第 9 个被拒"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0

    await reset_dut(dut)

    # 连写 17 个 (深度16 + 1, 最后一个应被拒)
    dut.wr_en.value = 1
    for i in range(17):
        dut.wr_data.value = 0xA0 + i
        await RisingEdge(dut.clk)

    await Timer(1, unit="step")
    assert dut.full.value == 1, "write 17: full should be 1"

    # 满时再写一拍, full 应保持, 数据不被破坏
    dut.wr_data.value = 0xFF
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")
    assert dut.full.value == 1, "write when full: full stays 1"
    dut.wr_en.value = 0


@cocotb.test()
async def test_read_empty(dut):
    """测试3: 写满再读空, 数据顺序正确, 读完后 empty=1"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0

    await reset_dut(dut)

    # 先写满 16 个
    dut.wr_en.value = 1
    for i in range(16):
        dut.wr_data.value = 0xA0 + i
        await RisingEdge(dut.clk)
    dut.wr_en.value = 0
    await Timer(1, unit="step")
    assert dut.full.value == 1, "prefill 16: full should be 1"

    # 读 16 个, 检查顺序
    # 注意: rd_data 是组合输出, 沿处理后指针已前进,
    # 所以要在"沿之前"采样本拍将要读出的数据
    dut.rd_en.value = 1
    for i in range(16):
        await Timer(1, unit="step")
        assert dut.rd_data.value == 0xA0 + i, \
            f"read {i}: got {dut.rd_data.value:#x}, expect {0xA0 + i:#x}"
        await RisingEdge(dut.clk)

    await Timer(1, unit="step")
    assert dut.empty.value == 1, "read 16: empty should be 1"

    # 空时再读, empty 保持, 指针不动
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")
    assert dut.empty.value == 1, "read when empty: empty stays 1"
    dut.rd_en.value = 0


@cocotb.test()
async def test_simult_rw(dut):
    """测试4: 同时读写 4 拍, 数据不丢不乱, cnt 不变"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.wr_en.value = 0
    dut.rd_en.value = 0
    dut.wr_data.value = 0

    await reset_dut(dut)

    # 预填 8 个 (深度16, 保持半满, 给同时读写留空间)
    dut.wr_en.value = 1
    for i in range(8):
        dut.wr_data.value = 0x10 + i
        await RisingEdge(dut.clk)
    dut.wr_en.value = 0
    await Timer(1, unit="step")
    assert not dut.full.value and not dut.empty.value, "prefill 8: mid state"

    # 同时读写 8 拍: 沿之前采样"将读出的旧数据", 沿上写入新数据
    for i in range(8):
        dut.wr_en.value = 1
        dut.rd_en.value = 1
        dut.wr_data.value = 0x20 + i
        await Timer(1, unit="step")
        assert dut.rd_data.value == 0x10 + i, \
            f"simul-rw {i}: got {dut.rd_data.value:#x}, expect {0x10 + i:#x}"
        await RisingEdge(dut.clk)

    await Timer(1, unit="step")
    assert not dut.full.value and not dut.empty.value, \
        "after simult-rw: cnt unchanged"

    # 把剩下 8 个排空, 验证新数据都进去了
    dut.wr_en.value = 0
    for i in range(8):
        await Timer(1, unit="step")
        assert dut.rd_data.value == 0x20 + i, \
            f"drain {i}: got {dut.rd_data.value:#x}, expect {0x20 + i:#x}"
        await RisingEdge(dut.clk)

    await Timer(1, unit="step")
    assert dut.empty.value == 1, "drain done: empty should be 1"
    dut.rd_en.value = 0
