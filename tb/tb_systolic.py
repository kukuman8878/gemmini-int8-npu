# tb/tb_systolic.py : NxN 脉动阵列测试 (自适应 4x4 / 8x8)
#   - 顶层为参数化 systolic (默认 N=4, c_flat 接口) 或 systolic_8x8 (c_flat 接口)
#   - 顶层为 systolic_4x4 (c_00..c_33 拍平接口)
#   - skew 由本驱动端完成: 行 i 在第 (i+k) 拍放 A[i][k], 列 j 在第 (j+k) 拍放 B[k][j]
import math
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden_model import matmul_ref

N = None


def detect_n(dut):
    if hasattr(dut, "c_flat"):
        return int(round(math.sqrt(len(dut.c_flat))))
    return 4


async def reset_dut(dut):
    dut.rst_n.value = 0
    for i in range(N):
        dut.a_row[i].value = 0
        dut.b_col[i].value = 0
        dut.en_a[i].value = 0
        dut.en_b[i].value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def drive_cycle(dut, A, B, cycle):
    """斜排喂数: 行 i 在第 (i+k) 拍放 A[i][k]"""
    for i in range(N):
        k = cycle - i
        if 0 <= k < N:
            dut.a_row[i].value = A[i][k]
            dut.en_a[i].value = 1
        else:
            dut.a_row[i].value = 0
            dut.en_a[i].value = 0
    for j in range(N):
        k = cycle - j
        if 0 <= k < N:
            dut.b_col[j].value = B[k][j]
            dut.en_b[j].value = 1
        else:
            dut.b_col[j].value = 0
            dut.en_b[j].value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


def read_c(dut):
    """读回 NxN 结果 (适配 c_flat 与 c_ij 两种接口)"""
    C = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            if hasattr(dut, "c_flat"):
                v = dut.c_flat[i * N + j].value
            else:
                v = getattr(dut, f"c_{i}{j}").value
            C[i][j] = v.signed_integer
    return C


async def run_matmul(dut, A, B):
    """喂矩阵, 读回 NxN 结果"""
    await reset_dut(dut)
    cycles = 3 * N - 2
    for cycle in range(cycles):
        await drive_cycle(dut, A, B, cycle)
    return read_c(dut)


def make_identity():
    return [[1 if i == j else 0 for j in range(N)] for i in range(N)]


async def check_pair(dut, A, B, tag):
    got = await run_matmul(dut, A, B)
    want = matmul_ref(A, B)
    fails = 0
    for i in range(N):
        for j in range(N):
            if got[i][j] != want[i][j]:
                fails += 1
                dut._log.error(
                    "[%s] MISMATCH at (%d,%d): got %d, want %d\n  A=%s\n  B=%s",
                    tag, i, j, got[i][j], want[i][j], A, B)
                if fails >= 5:
                    return fails
    return fails


@cocotb.test()
async def test_directed(dut):
    """定向: 单位阵 x 单位阵 = 单位阵"""
    global N
    N = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    I = make_identity()
    fails = await check_pair(dut, I, I, "IxI")
    dut._log.info("directed IxI (%dx%d) done", N, N)
    assert fails == 0, f"{fails} mismatches in directed test"


@cocotb.test()
async def test_random_matmul(dut):
    """随机: 随机 INT8 矩阵, Scoreboard 对比"""
    global N
    N = detect_n(dut)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    random.seed(2024)
    NPAIRS = 20
    fails = 0

    for n in range(NPAIRS):
        A = [[random.randint(-128, 127) for _ in range(N)] for _ in range(N)]
        B = [[random.randint(-128, 127) for _ in range(N)] for _ in range(N)]
        fails += await check_pair(dut, A, B, f"random#{n}")
        if fails >= 5:
            break

    dut._log.info("random matmul done: %d pairs of %dx%d", NPAIRS, N, N)
    assert fails == 0, f"{fails} mismatches!"
