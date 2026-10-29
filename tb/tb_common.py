# tb/tb_common.py : npu_top 端到端 Driver/Monitor 共享助手 (不含 @cocotb.test)
#   tb_top 与 tb_regression 复用; 握手语义与 docs/03 §3 一致
import random

from cocotb.triggers import RisingEdge, Timer

from scoreboard import Scoreboard

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
    """Scoreboard 比对 (逐元素精确), 返回失败数"""
    return Scoreboard(log=dut._log.error, name=tag).check_matrix(got, want, tag)


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
    """等 out_valid (可先反压 hold_ready 拍), 读回结果并完成握手
    反压期间逐拍读值, 与最终结果比对验证 out_c 稳定性"""
    while not int(dut.out_valid.value):
        await edge(dut)
    hold_reads = []
    for _ in range(hold_ready):              # 反压: out_ready=0 期间验证数据稳定
        assert int(dut.out_valid.value) == 1, "out_valid must hold under backpressure"
        hold_reads.append(read_out_c(dut))
        await edge(dut)
    C = read_out_c(dut)
    for hc in hold_reads:                    # 反压期间每次读值必须与最终结果一致
        fails = compare(dut, hc, C, "backpressure-stable")
        assert fails == 0, "out_c changed under backpressure"
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
