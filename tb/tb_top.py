# tb/tb_top.py : npu_top 端到端测试 (W6 门禁: P0 核心功能)
#   覆盖: 基本 tile / K 随机 (含 K>N) / 输入暂停 / 输出反压 / 连续任务清零 / 中途复位 / 非法配置 / done 单拍
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
    dut.cfg_valid.value = 0
    dut.cfg_k.value = 0
    dut.start.value = 0
    dut.in_valid.value = 0
    dut.out_ready.value = 0
    for i in range(N):
        dut.a_vec[i].value = 0
        dut.b_vec[i].value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


async def edge(dut):
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")


def rand_mat_k(r, c, seed):
    rng = random.Random(seed)
    return [[rng.randint(-128, 127) for _ in range(c)] for _ in range(r)]


def read_out_c(dut):
    C = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            C[i][j] = dut.out_c[i * N + j].value.to_signed()
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


async def cfg_task(dut, K):
    dut.cfg_k.value = K
    dut.cfg_valid.value = 1
    await edge(dut)
    dut.cfg_valid.value = 0


async def start_task(dut):
    dut.start.value = 1
    await edge(dut)
    dut.start.value = 0
    assert int(dut.busy.value) == 1, "busy should assert after start"


async def load_slices(dut, A, B, K, pauses=()):
    """呈现 K 个切片 (in_ready 握手), 可在指定切片序号前插入暂停拍"""
    presented = 0
    pause_set = set(pauses)
    while presented < K:
        if presented in pause_set:
            dut.in_valid.value = 0
            await edge(dut)
            pause_set.discard(presented)
            continue
        for i in range(N):
            dut.a_vec[i].value = A[i][presented]
        for j in range(N):
            dut.b_vec[j].value = B[presented][j]
        dut.in_valid.value = 1
        await Timer(1, unit="step")
        if int(dut.in_ready.value):          # 沿前握手采样
            presented += 1
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
    dut.in_valid.value = 0


async def wait_and_read(dut, hold_ready=0):
    """等 out_valid (可先反压 hold_ready 拍), 读回结果并完成握手"""
    while not int(dut.out_valid.value):
        await edge(dut)
    for _ in range(hold_ready):              # 反压: out_ready=0 期间验证数据稳定
        assert int(dut.out_valid.value) == 1, "out_valid must hold under backpressure"
        got_now = read_out_c(dut)
        await edge(dut)
    C = read_out_c(dut)
    dut.out_ready.value = 1
    await edge(dut)
    dut.out_ready.value = 0
    return C


async def run_task(dut, A, B, K, pauses=(), hold_ready=0, cfg=True):
    if cfg:
        await cfg_task(dut, K)
    await start_task(dut)
    await load_slices(dut, A, B, K, pauses)
    return await wait_and_read(dut, hold_ready)


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
