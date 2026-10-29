# tb/tb_systolic.py : NxN 脉动阵列测试 (自适应 4x4 / 8x8)
#   顶层: systolic_4x4 (c_00..c_33 拍平接口) 或 systolic_8x8 (c_flat 接口)
#   skew 由本驱动端完成: 行 i 在第 (i+k) 拍放 A[i][k], 列 j 在第 (j+k) 拍放 B[k][j]
#   覆盖: V01 零矩阵 / V04 K 部分归约 / en 门控 / V09 连续任务 / V10 中途复位
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden_model import matmul_ref


def detect_n(dut):
    """按 DUT 接口自适应阵列规模: c_flat 或 c_ij 拍平端口"""
    if hasattr(dut, "c_flat"):
        return int(round(math.sqrt(len(dut.c_flat))))
    return 4


async def reset_dut(dut, n):
    dut.rst_n.value = 0
    for i in range(n):
        dut.a_row[i].value = 0
        dut.b_col[i].value = 0
        dut.en_a[i].value = 0
        dut.en_b[i].value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def drive_cycle(dut, n, A, B, cycle, en_on=True, garbage=None, k_limit=None):
    """斜排喂数: 行 i 在第 (i+k) 拍放 A[i][k]。
    en_on=False 时数据照放但 en=0 (测试无效拍不累加);
    garbage 非 None 时, 窗口外放 garbage 数据 (测试 en=0 门控数据);
    k_limit 非 None 时, 仅 k < k_limit 的窗口项有效 (测试 K 部分归约)"""
    limit = n if k_limit is None else k_limit
    for i in range(n):
        k = cycle - i
        if 0 <= k < limit and en_on:
            dut.a_row[i].value = A[i][k]
            dut.en_a[i].value = 1
        else:
            dut.a_row[i].value = 0 if garbage is None else garbage(i, k, cycle)
            dut.en_a[i].value = 0
    for j in range(n):
        k = cycle - j
        if 0 <= k < limit and en_on:
            dut.b_col[j].value = B[k][j]
            dut.en_b[j].value = 1
        else:
            dut.b_col[j].value = 0 if garbage is None else garbage(j, k, cycle)
            dut.en_b[j].value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


def read_c(dut, n):
    """读回 NxN 结果 (适配 c_flat 与 c_ij 两种接口)"""
    C = [[0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if hasattr(dut, "c_flat"):
                v = dut.c_flat[i * n + j].value
            else:
                v = getattr(dut, f"c_{i}{j}").value
            C[i][j] = v.signed_integer
    return C


def rand_mat(n, seed):
    rng = random.Random(seed)
    return [[rng.randint(-128, 127) for _ in range(n)] for _ in range(n)]


def compare(dut, got, want, tag):
    fails = 0
    for i in range(len(want)):
        for j in range(len(want)):
            if got[i][j] != want[i][j]:
                fails += 1
                dut._log.error("[%s] MISMATCH at (%d,%d): got %d, want %d", tag, i, j, got[i][j], want[i][j])
                if fails >= 5:
                    return fails
    return fails


async def run_matmul(dut, n, A, B, reset=True):
    if reset:
        await reset_dut(dut, n)
    for cycle in range(3 * n - 2):
        await drive_cycle(dut, n, A, B, cycle)
    return read_c(dut, n)


@cocotb.test()
async def test_directed_identity(dut):
    """V01(部分): 单位阵 x 单位阵 = 单位阵"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    I = [[1 if i == j else 0 for j in range(n)] for i in range(n)]
    got = await run_matmul(dut, n, I, I)
    fails = compare(dut, got, matmul_ref(I, I), "IxI")
    dut._log.info("directed IxI (%dx%d) done", n, n)
    assert fails == 0, f"{fails} mismatches in directed test"


@cocotb.test()
async def test_zero_matrix(dut):
    """V01: 零矩阵 x 零矩阵 = 零矩阵 (数据通路与初始清零)"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    Z = [[0] * n for _ in range(n)]
    got = await run_matmul(dut, n, Z, Z)
    fails = compare(dut, got, matmul_ref(Z, Z), "ZxZ")
    assert fails == 0, f"{fails} mismatches in zero matrix test"


@cocotb.test()
async def test_en_gating(dut):
    """en=0 且数据非零时, 累加器必须保持 0 (无效拍不累加)"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut, n)
    A = rand_mat(n, 11)
    B = rand_mat(n, 12)
    for cycle in range(2 * n):
        await drive_cycle(dut, n, A, B, cycle, en_on=False)
    got = read_c(dut, n)
    want = [[0] * n for _ in range(n)]
    fails = compare(dut, got, want, "en=0 gating")
    assert fails == 0, f"{fails} mismatches in en-gating test"


@cocotb.test()
async def test_partial_k(dut):
    """V04: K 部分归约 (K<N), 窗口外给垃圾数据+en=0, 结果只含前 K 项"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    A = rand_mat(n, 21)
    B = rand_mat(n, 22)

    def garbage(idx, k, cycle):
        return (0x5A + 3 * idx + cycle) & 0x7F

    for K in (1, n // 2, n - 1):
        await reset_dut(dut, n)
        # 第 k 项累加发生在 PE(i,j) 的第 (i+j+k) 拍, 最晚 i=j=n-1,k=K-1
        cycles = 2 * n + K - 2
        for cycle in range(cycles):
            # k<K 有效; k>=K 与窗口外均为垃圾数据 + en=0
            await drive_cycle(dut, n, A, B, cycle, garbage=garbage, k_limit=K)
        got = read_c(dut, n)
        want = matmul_ref(
            [row[:K] for row in A],   # A[:, :K] : n x K
            B[:K],                    # B[:K, :] : K x n
        )
        fails = compare(dut, got, want, f"partial-K={K}")
        dut._log.info("partial K=%d done", K)
        assert fails == 0, f"{fails} mismatches for K={K}"


@cocotb.test()
async def test_back_to_back(dut):
    """V09: 连续任务 (中间不复位) -> 累加语义: C1 + C2, 无意外清零"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    A1, B1 = rand_mat(n, 31), rand_mat(n, 32)
    A2, B2 = rand_mat(n, 33), rand_mat(n, 34)
    got = await run_matmul(dut, n, A1, B1, reset=True)
    got = await run_matmul(dut, n, A2, B2, reset=False)
    want = matmul_ref(A1, B1)
    w2 = matmul_ref(A2, B2)
    for i in range(n):
        for j in range(n):
            want[i][j] += w2[i][j]
    fails = compare(dut, got, want, "back-to-back")
    assert fails == 0, f"{fails} mismatches in back-to-back test"


@cocotb.test()
async def test_mid_reset(dut):
    """V10: 计算中途复位 -> 累加器清零, 之后全新任务结果正确 (无半截残留)"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut, n)
    A1, B1 = rand_mat(n, 41), rand_mat(n, 42)
    for cycle in range(n):          # 只跑前半段
        await drive_cycle(dut, n, A1, B1, cycle)
    await reset_dut(dut, n)         # 中途复位
    A2, B2 = rand_mat(n, 43), rand_mat(n, 44)
    got = await run_matmul(dut, n, A2, B2, reset=False)
    fails = compare(dut, got, matmul_ref(A2, B2), "mid-reset")
    assert fails == 0, f"{fails} mismatches in mid-reset test"


@cocotb.test()
async def test_random_matmul(dut):
    """V06: 随机 INT8 矩阵, Scoreboard 对比"""
    n = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    random.seed(2024)
    NPAIRS = 20
    fails = 0

    for t in range(NPAIRS):
        A = [[random.randint(-128, 127) for _ in range(n)] for _ in range(n)]
        B = [[random.randint(-128, 127) for _ in range(n)] for _ in range(n)]
        got = await run_matmul(dut, n, A, B)
        fails += compare(dut, got, matmul_ref(A, B), f"random#{t}")
        if fails >= 5:
            break

    dut._log.info("random matmul done: %d pairs of %dx%d", NPAIRS, n, n)
    assert fails == 0, f"{fails} mismatches!"
