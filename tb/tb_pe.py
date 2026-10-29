# tb/tb_pe.py : 单 PE 全语义测试 (转发/使能/累加/复位)
#   自适应位宽 (默认 8/32, 亦用于 pe_16_64 参数组合验证)
#   波形: make sim_pe WAVES=1 会在 sim_build/sim_pe/ 下生成 fst
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden_model import mac_ref_wrap


def dut_widths(dut):
    """返回 (A 通道位宽, 累加器位宽)"""
    return len(dut.a_in), len(dut.acc)


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.acc_clr.value = 0
    dut.a_in.value = 0
    dut.b_in.value = 0
    dut.en_a.value = 0
    dut.en_b.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def step(dut, a, b, en_a, en_b):
    """驱动一拍并返回沿后的输出元组 (a_out, b_out, en_a_out, en_b_out, acc)"""
    dut.a_in.value = a
    dut.b_in.value = b
    dut.en_a.value = en_a
    dut.en_b.value = en_b
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")
    return (
        dut.a_out.value.to_signed(),
        dut.b_out.value.to_signed(),
        int(dut.en_a_out.value),
        int(dut.en_b_out.value),
        dut.acc.value.to_signed(),
    )


@cocotb.test()
async def test_reset_state(dut):
    """复位后所有寄存器清零"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    assert int(dut.a_out.value) == 0 and int(dut.b_out.value) == 0
    assert int(dut.en_a_out.value) == 0 and int(dut.en_b_out.value) == 0
    assert dut.acc.value.to_signed() == 0


@cocotb.test()
async def test_forward_delay(dut):
    """寄存转发时序: 无时钟沿时改变输入, 输出必须保持旧值 (组合直通会在此失败)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    _, _, _, _, _ = await step(dut, 11, 0, 0, 0)    # 沿后: a_out=11, b_out=0
    dut.a_in.value = 99                             # 改输入, 不打拍
    dut.b_in.value = 98
    await Timer(1, unit="step")                     # 组合逻辑充分传播
    ao = dut.a_out.value.to_signed()
    bo = dut.b_out.value.to_signed()
    assert ao == 11 and bo == 0, f"no-edge: got ({ao},{bo}), want (11,0)"

    # en 标志与 acc 同属一个 always 块, 一并验证无沿保持
    _, _, _, _, _ = await step(dut, 11, 5, 1, 1)    # 沿后: en_out=1/1, acc=55
    dut.en_a.value = 0                              # 改 en, 不打拍
    dut.en_b.value = 0
    await Timer(1, unit="step")
    eao = int(dut.en_a_out.value)
    ebo = int(dut.en_b_out.value)
    acc = dut.acc.value.to_signed()
    assert eao == 1 and ebo == 1, f"no-edge en: got ({eao},{ebo}), want (1,1)"
    assert acc == 55, f"no-edge acc: got {acc}, want 55"
    dut._log.info("forward delay: register (not combinational) behavior confirmed")


@cocotb.test()
async def test_forwarding(dut):
    """a/b 与 en 标志均寄存 1 拍转发 (en 组合均无累加副作用)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    cases = [(5, -7, 1, 0), (-128, 127, 0, 1), (0, 0, 0, 1), (63, -64, 0, 0)]
    for a, b, en_a, en_b in cases:
        ao, bo, eao, ebo, acc = await step(dut, a, b, en_a, en_b)
        assert ao == a and bo == b, f"forward: got ({ao},{bo}), want ({a},{b})"
        assert eao == en_a and ebo == en_b, f"en forward: got ({eao},{ebo}), want ({en_a},{en_b})"
        assert acc == 0, f"forward with en=({en_a},{en_b}) must not accumulate, acc={acc}"
    dut._log.info("forwarding: %d cases passed", len(cases))


@cocotb.test()
async def test_accumulate(dut):
    """en_a=en_b=1 连续累加 (边界值), 与回绕参考模型比对"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    acc_bits = dut_widths(dut)[1]
    acc = 0
    cases = [(3, 4), (-5, 6), (-128, -128), (127, 127), (-128, 127)]
    for a, b in cases:
        _, _, _, _, got = await step(dut, a, b, 1, 1)
        acc = mac_ref_wrap(acc, a, b, 1, acc_bits=acc_bits)
        assert got == acc, f"accumulate a={a} b={b}: got {got}, want {acc}"
    dut._log.info("accumulate: %d cases passed", len(cases))


@cocotb.test()
async def test_en_gating(dut):
    """单通道/双通道无效拍不累加 (数据非零), acc 保持"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # 先建立非零累加值
    _, _, _, _, acc = await step(dut, 5, 5, 1, 1)   # acc = 25
    # (en_a, en_b) 三种无效组合, 数据非零
    for en_a, en_b in [(0, 1), (1, 0), (0, 0)]:
        _, _, _, _, got = await step(dut, 7, 9, en_a, en_b)
        assert got == acc, f"en=({en_a},{en_b}) with data 7,9: acc changed {acc}->{got}"
    dut._log.info("en gating: 3 invalid combos keep acc=%d", acc)


@cocotb.test()
async def test_mid_reset(dut):
    """累加若干拍后复位, acc 清零且转发寄存器清零"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for _ in range(3):
        await step(dut, 4, 4, 1, 1)
    assert dut.acc.value.to_signed() == 48

    await reset_dut(dut)
    assert dut.acc.value.to_signed() == 0
    assert int(dut.a_out.value) == 0 and int(dut.en_a_out.value) == 0
    dut._log.info("mid reset: acc cleared")


@cocotb.test()
async def test_random(dut):
    """随机 1000 拍: 随机数据 + 随机 en 组合, Scoreboard 逐拍比对 (位宽自适应)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    a_bits, acc_bits = dut_widths(dut)
    lo, hi = -(1 << (a_bits - 1)), (1 << (a_bits - 1)) - 1

    random.seed(2026)
    acc = 0
    fails = 0
    done = 0
    for i in range(1000):
        a = random.randint(lo, hi)
        b = random.randint(lo, hi)
        en_a = random.choice([0, 1])
        en_b = random.choice([0, 1])
        ao, bo, eao, ebo, got = await step(dut, a, b, en_a, en_b)
        acc = mac_ref_wrap(acc, a, b, int(en_a and en_b), acc_bits=acc_bits)
        done = i + 1
        ok = (ao == a and bo == b and eao == en_a and ebo == en_b
              and got == acc)
        if not ok:
            fails += 1
            dut._log.error("MISMATCH #%d: a=%d b=%d en=(%d,%d) got acc=%d want=%d",
                           i, a, b, en_a, en_b, got, acc)
            if fails >= 5:
                break

    if fails:
        dut._log.info("random PE test aborted after %d cycles", done)
    else:
        dut._log.info("random PE test done: %d cycles", done)
    assert fails == 0, f"{fails} mismatches!"


@cocotb.test()
async def test_acc_clr(dut):
    """acc_clr 清零累加器 (任务边界), 转发不冻结"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for _ in range(3):
        await step(dut, 4, 4, 1, 1)
    assert dut.acc.value.to_signed() == 48

    dut.acc_clr.value = 1
    await step(dut, 0, 0, 0, 0)
    assert dut.acc.value.to_signed() == 0, "acc cleared by acc_clr"
    dut.acc_clr.value = 0

    _, _, _, _, acc = await step(dut, 3, 5, 1, 1)
    assert acc == 15, f"accumulate after clear: got {acc}"
    dut._log.info("acc_clr ok")
