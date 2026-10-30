# tb/tb_bench.py : 周期测量基准 (W10)
#   测量 npu_top 单 tile 任务周期, 通过 state 观测分解 LOAD/DRAIN/OUTPUT 分量
#   断言: load == K, drain == 2N-1, output == 1 (与 controller 语义一致, 防漂移)
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from tb_common import reset_dut, cfg_task, N

KS = [1, 2, 4, 8, 16, 64, 256]
STATE_LOAD = 1
STATE_DRAIN = 2
STATE_OUT = 3


async def _measure_tile(dut, K):
    await reset_dut(dut)
    await cfg_task(dut, K)

    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await Timer(1, unit="step")

    phases = {STATE_LOAD: 0, STATE_DRAIN: 0, STATE_OUT: 0}
    total = 0
    out_seen = False
    while True:
        s = int(dut.state.value)
        if s in phases:
            phases[s] += 1
        if s == STATE_LOAD:
            dut.in_valid.value = 1      # LOAD 阶段持续呈现切片
        else:
            dut.in_valid.value = 0
        if s == STATE_OUT:
            out_seen = True
            dut.out_ready.value = 1      # OUTPUT 单拍握手完成
        else:
            dut.out_ready.value = 0
        if s == 0 and out_seen:          # 回到 IDLE 且已过 OUTPUT
            break
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
        total += 1
    return phases, total


@cocotb.test()
async def test_tile_cycles(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    rows = []
    for K in KS:
        phases, total = await _measure_tile(dut, K)
        l, d, o = phases[STATE_LOAD], phases[STATE_DRAIN], phases[STATE_OUT]
        assert l == K, f"K={K}: load={l} != {K}"
        assert d == 2 * N - 1, f"K={K}: drain={d} != {2*N-1}"
        assert o == 1, f"K={K}: output={o} != 1"
        rows.append((K, l, d, o, total))
        dut._log.info(f"K={K}: load={l} drain={d} out={o} total={total}")
    dut._log.info("summary: " + "; ".join(
        f"K={r[0]}:load={r[1]},drain={r[2]},out={r[3]},total={r[4]}" for r in rows))
