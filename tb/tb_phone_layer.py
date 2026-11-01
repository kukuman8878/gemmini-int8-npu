# tb/tb_phone_layer.py : W14 真实 1×1 Conv→GEMM 的 RTL 一致性验证
#   读 conversion.py 生成的切块数据, 用 npu_top 逐 tile×K分块 计算, 与 golden_tiles (INT32) 逐元素比对
#   环境变量 TILES 控制跑多少列 tile (默认全部 mi=0 行, 即 N_tiles=320)
import os
import json
import numpy as np
import cocotb
from cocotb.clock import Clock

from tb_common import reset_dut, run_task

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "benchmarks", "phone_layer_01")


@cocotb.test()
async def test_phone_layer(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset_dut(dut)

    tiling = json.load(open(os.path.join(HERE, "tiling.json")))
    golden_tiles = np.load(os.path.join(HERE, "golden_tiles.npy"))
    A_pad = np.load(os.path.join(HERE, "a_pad_int8.npy"))
    B_pad = np.load(os.path.join(HERE, "b_pad_int8.npy"))
    bias = np.load(os.path.join(HERE, "bias_int32.npy"))

    M_tiles, N_tiles = tiling["M_tiles"], tiling["N_tiles"]
    K_blocks = tiling["K_blocks"]
    K_offsets = np.cumsum([0] + K_blocks[:-1])

    tiles_env = os.environ.get("TILES", "").strip()
    max_tiles = int(tiles_env) if tiles_env else N_tiles
    mi = 0

    checked = 0
    mismatches = 0
    for nj in range(min(N_tiles, max_tiles)):
        # K 分块累加 (软件累加, npu_top 每次任务边界清零)
        C = np.zeros((4, 4), dtype=np.int64)
        for kb, ksize in enumerate(K_blocks):
            k0 = int(K_offsets[kb])
            A_tile = [[int(A_pad[mi * 4 + i, k0 + k]) for k in range(ksize)] for i in range(4)]
            B_tile = [[int(B_pad[k0 + k, nj * 4 + j]) for j in range(4)] for k in range(ksize)]
            got = await run_task(dut, A_tile, B_tile, ksize)
            C += np.array(got, dtype=np.int64)

        # + bias (最终累加一次)
        C_final = C + bias[nj * 4:nj * 4 + 4].reshape(1, 4)
        golden = golden_tiles[mi, nj]
        for i in range(4):
            for j in range(4):
                checked += 1
                if int(C_final[i, j]) != int(golden[i, j]):
                    mismatches += 1
                    dut._log.error(
                        f"MISMATCH tile(mi={mi},nj={nj})[{i}][{j}]: got={C_final[i, j]} want={golden[i, j]}")

    dut._log.info(f"phone_layer: checked {checked} INT32 elements, {mismatches} mismatches")
    assert mismatches == 0, f"{mismatches} mismatches"
