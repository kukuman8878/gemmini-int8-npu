# tb/tb_skew.py : input_skew + 4x4 阵列联合测试 (skew 在 RTL 内完成)
#   驱动: 第 k 拍呈现列切片 a_vec[i]=A[i][k] / 行切片 b_vec[j]=B[k][j], k<K 时 valid=1
#   时序: K 拍呈现 + (2N-1) 拍排空后结果就绪
#   覆盖: 黄金向量 / 零矩阵 / K 随机 (含 K>N) / en 门控 / 连续任务 / 中途复位
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from golden_model import matmul_ref

N = 4


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.acc_clr.value = 0
    dut.valid.value = 0
    for i in range(N):
        dut.a_vec[i].value = 0
        dut.b_vec[i].value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


def garbage(idx, k, cycle):
    return (0x2D + 4 * idx + cycle) % 126 + 1   # 恒非零


async def drive_slice(dut, A, B, K, k, cycle):
    """第 k 拍切片: k<K 时 valid=1 带真实数据, 否则垃圾数据 + valid=0"""
    if 0 <= k < K:
        for i in range(N):
            dut.a_vec[i].value = A[i][k]
        for j in range(N):
            dut.b_vec[j].value = B[k][j]
        dut.valid.value = 1
    else:
        for i in range(N):
            dut.a_vec[i].value = garbage(i, k, cycle)
            dut.b_vec[i].value = garbage(i, k, cycle)
        dut.valid.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


def read_c(dut):
    C = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            C[i][j] = getattr(dut, f"c_{i}{j}").value.to_signed()
    return C


def compare(dut, got, want, tag):
    fails = 0
    for i in range(N):
        for j in range(N):
            if got[i][j] != want[i][j]:
                fails += 1
                dut._log.error("[%s] MISMATCH at (%d,%d): got %d, want %d", tag, i, j, got[i][j], want[i][j])
                if fails >= 5:
                    return fails
    return fails


def rand_mat_k(r, c, seed):
    rng = random.Random(seed)
    return [[rng.randint(-128, 127) for _ in range(c)] for _ in range(r)]


async def run_tile(dut, A, B, K, reset=True, drain=True):
    """完整跑一个 tile: K 拍呈现 + 2N-1 拍排空"""
    if reset:
        await reset_dut(dut)
    for cycle in range(K):
        await drive_slice(dut, A, B, K, cycle, cycle)
    if drain:
        for d in range(2 * N - 1):
            await drive_slice(dut, A, B, K, K + d, K + d)
    return read_c(dut)


@cocotb.test()
async def test_golden_2x2(dut):
    """黄金向量 (接口规范 §4): A=[[1,2],[3,4]], B=[[5,6],[7,8]], 零填充至 4x4"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    K = 2
    A = [[1, 2], [3, 4], [0, 0], [0, 0]]
    B = [[5, 6, 0, 0], [7, 8, 0, 0]]
    got = await run_tile(dut, A, B, K)
    want = matmul_ref(A, B)
    assert compare(dut, got, want, "golden-2x2") == 0


@cocotb.test()
async def test_zero(dut):
    """零矩阵, 全零输出"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    K = 4
    A = [[0] * K for _ in range(N)]
    B = [[0] * N for _ in range(K)]
    got = await run_tile(dut, A, B, K)
    assert compare(dut, got, matmul_ref(A, B), "zero") == 0


@cocotb.test()
async def test_en_gating(dut):
    """valid=0 且垃圾数据非零: 不累加"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    A = rand_mat_k(N, 8, 61)
    B = rand_mat_k(8, N, 62)
    for cycle in range(2 * N):
        await drive_slice(dut, A, B, 0, -1, cycle)   # k=-1 恒无效
    for d in range(2 * N - 1):                       # 排空, 确保深层 PE 已见全垃圾
        await drive_slice(dut, A, B, 0, -1, 2 * N + d)
    got = read_c(dut)
    assert compare(dut, got, [[0] * N for _ in range(N)], "en-gating") == 0


@cocotb.test()
async def test_random_k(dut):
    """K ∈ {1,2,4,8,16} 随机 tile (含 K>N), 与黄金模型精确比对"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    for K in (1, 2, 4, 8, 16):
        A = rand_mat_k(N, K, 70 + K)
        B = rand_mat_k(K, N, 80 + K)
        got = await run_tile(dut, A, B, K)
        fails = compare(dut, got, matmul_ref(A, B), f"K={K}")
        dut._log.info("random tile K=%d done", K)
        assert fails == 0, f"{fails} mismatches for K={K}"


@cocotb.test()
async def test_back_to_back(dut):
    """连续任务 (不复位): 累加语义 C1+C2 (K 相等与 K 不等两种边界)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    for K1, K2 in ((4, 4), (4, 2), (2, 6)):
        A1, B1 = rand_mat_k(N, K1, 91), rand_mat_k(K1, N, 92)
        A2, B2 = rand_mat_k(N, K2, 93), rand_mat_k(K2, N, 94)
        got = await run_tile(dut, A1, B1, K1, reset=True, drain=False)   # 不排空直接下一任务
        got = await run_tile(dut, A2, B2, K2, reset=False)
        want = matmul_ref(A1, B1)
        w2 = matmul_ref(A2, B2)
        for i in range(N):
            for j in range(N):
                want[i][j] += w2[i][j]
        fails = compare(dut, got, want, f"back-to-back K1={K1} K2={K2}")
        assert fails == 0, f"{fails} mismatches for K1={K1} K2={K2}"


@cocotb.test()
async def test_mid_reset(dut):
    """呈现中途复位: 结果只含复位后的任务"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    A1, B1 = rand_mat_k(N, 4, 101), rand_mat_k(4, N, 102)
    for cycle in range(2):                       # 只呈现前 2 拍
        await drive_slice(dut, A1, B1, 4, cycle, cycle)
    await reset_dut(dut)                         # 中途复位
    A2, B2 = rand_mat_k(N, 4, 103), rand_mat_k(4, N, 104)
    got = await run_tile(dut, A2, B2, 4, reset=False)
    assert compare(dut, got, matmul_ref(A2, B2), "mid-reset") == 0
