import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from tb_common import N, reset_dut, cfg_task, start_task, load_slices

@cocotb.test()
async def probe(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    K = 2
    A = [[1,2],[3,4],[0,0],[0,0]]
    B = [[5,6,0,0],[7,8,0,0]]
    await cfg_task(dut, K)
    await start_task(dut)
    await load_slices(dut, A, B, K)
    for c in range(12):
        # 沿前采样 (与 SV always @posedge 读取 pre-edge 值一致)
        ov = int(dut.out_valid.value)
        flat = int(dut.u_sv.out_c_flat.value) & ((1 << 512) - 1)
        concat = 0
        for e in range(15, -1, -1):
            concat = (concat << 32) | (int(dut.out_c[e].value.to_signed()) & 0xFFFFFFFF)
        if ov and flat != concat:
            dut._log.error("PRE-EDGE cyc=%d flat=%0128x concat=%0128x", c, flat, concat)
        dut.out_ready.value = 1 if ov else 0
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
