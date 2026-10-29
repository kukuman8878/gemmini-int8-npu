# tb/tb_regression.py : 固定种子批量随机回归 (环境变量 SEED/PAIRS 驱动)
#   每次运行: SEED 种子 × 5 种 K ∈ {1,2,4,8,16} × PAIRS 组随机 tile, Scoreboard 精确比对
#   由 verification/random_regression.py 批量调用, 日志记录 DUT 版本/命令/种子
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "verification"))

import cocotb
from cocotb.clock import Clock

from golden_model import matmul_ref
from scoreboard import Scoreboard
from tb_common import N, reset_dut, run_task

SEED = int(os.environ.get("SEED", "2024"))
PAIRS = int(os.environ.get("PAIRS", "20"))
K_LIST = (1, 2, 4, 8, 16)


@cocotb.test()
async def test_seeded_random(dut):
    """SEED 驱动的批量随机回归: K_LIST × PAIRS 组随机 tile"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    rng = random.Random(SEED)
    sb = Scoreboard(log=dut._log.error, name=f"regression-seed{SEED}")

    for K in K_LIST:
        for p in range(PAIRS):
            A = [[rng.randint(-128, 127) for _ in range(K)] for _ in range(N)]
            B = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(K)]
            got = await run_task(dut, A, B, K)
            sb.check_matrix(got, matmul_ref(A, B), f"seed{SEED} K={K} pair#{p}")
            if sb.fails >= 5:
                break
        if sb.fails >= 5:
            break

    dut._log.info("seeded regression: seed=%d pairs=%d K=%s", SEED, PAIRS, K_LIST)
    dut._log.info(sb.summary())
    assert sb.fails == 0, f"{sb.fails} mismatches (seed={SEED})"
