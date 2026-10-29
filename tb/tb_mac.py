# tb/tb_mac.py : MAC 的 cocotb 测试 (边界定向 + 随机 Scoreboard)
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden_model import mac_ref, mac_ref_wrap


async def reset_dut(dut):
    """复位: rst_n 拉低 2 拍再放开"""
    dut.rst_n.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def do_mac(dut, a, b, acc, en):
    """执行一次 MAC 运算, 返回沿后稳定的 acc_out (有符号整数)"""
    dut.a.value = a          # cocotb 自动把负数转成对应位宽的补码
    dut.b.value = b
    dut.acc_in.value = acc
    dut.en.value = en
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")
    return dut.acc_out.value.to_signed()    # 按有符号解读 32 位结果


@cocotb.test()
async def test_boundary(dut):
    """定向测试: INT8 边界值"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    cases = [
        (0,     3,    4,    1, 12),
        (12,    -5,   6,    1, -18),
        (0,     -128, -128, 1, 16384),
        (0,     127,  127,  1, 16129),
        (0,     -128, 127,  1, -16256),
        (12345, 7,    7,    0, 12345),
    ]
    for acc, a, b, en, want in cases:
        got = await do_mac(dut, a, b, acc, en)
        assert got == want, \
            f"a={a} b={b} acc={acc} en={en}: got {got}, want {want}"
    dut._log.info("boundary test: %d cases passed", len(cases))


@cocotb.test()
async def test_random_mac(dut):
    """随机测试: 2000 组随机输入, Scoreboard 与黄金模型逐组对比"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    random.seed(2024)
    N = 2000
    fails = 0

    for i in range(N):
        a = random.randint(-128, 127)          # 全 INT8 范围
        b = random.randint(-128, 127)
        acc = random.randint(-2**20, 2**20)    # 安全范围, 防 32 位累加溢出
        en = random.choice([0, 0, 1, 1, 1])    # en=1 占多数 (模拟真实工作)

        got = await do_mac(dut, a, b, acc, en)         # DUT 实际
        want = mac_ref(acc, a, b, en)                  # 黄金模型期望

        if got != want:
            fails += 1
            dut._log.error("MISMATCH #%d: a=%d b=%d acc=%d en=%d -> got %d, want %d",
                           i, a, b, acc, en, got, want)
            if fails >= 5:
                break

    dut._log.info("random test done: %d ops", N)
    assert fails == 0, f"{fails} ops mismatched!"


@cocotb.test()
async def test_exhaustive_boundary(dut):
    """V03 增强: 全边界组合穷举 + 溢出回绕语义锁定
    a,b ∈ {-128,-127,-1,0,1,126,127}; acc ∈ {INT32_MIN,-2^20,0,2^20,INT32_MAX}
    共 7x7x5=245 组, 用 32 位 2 补码回绕参考模型精确比对"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    avals = [-128, -127, -1, 0, 1, 126, 127]
    accs = [-(2**31), -(2**20), 0, 2**20, 2**31 - 1]
    fails = 0
    ncases = 0

    for a in avals:
        for b in avals:
            for acc in accs:
                got = await do_mac(dut, a, b, acc, 1)
                want = mac_ref_wrap(acc, a, b, 1)
                ncases += 1
                if got != want:
                    fails += 1
                    dut._log.error("MISMATCH: a=%d b=%d acc=%d -> got %d, want %d",
                                   a, b, acc, got, want)
                    if fails >= 5:
                        break
            if fails >= 5:
                break
        if fails >= 5:
            break

    dut._log.info("exhaustive boundary test done: %d cases", ncases)
    assert fails == 0, f"{fails} cases mismatched!"
