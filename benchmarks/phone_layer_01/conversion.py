#!/usr/bin/env python3
# conversion.py : conv→GEMM 量化对齐 + 切块 + K 分块 + tiling (W14 §1.2/§4)
#   关键契约: MobileNetV2 为 uint8 非对称量化 (zero_point≠128), 减零点后值域可能轻微超出 int8;
#   自研 RTL 输入为 signed 8bit。故对齐步骤: clamp(q - zero_point, -128, 127) → int8。
#   golden 用相同 int8 值做 INT32 累加, 保证 RTL 与 golden 同一整型语义下逐元素一致。
#   输出: tiling.json + golden_tiles.npy + a_int8.npy/pad + b_int8.npy/pad
#   用法: python3 benchmarks/phone_layer_01/conversion.py
import os
import json
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ARRAY = 4
K_MAX = 256

A = np.load(os.path.join(HERE, "input_a_int8.npy"))            # [M,K] uint8 (raw)
B = np.load(os.path.join(HERE, "weight_b_int8.npy"))           # [K,N] uint8 (raw)
bias = np.load(os.path.join(HERE, "bias_int32.npy"))           # [N] int32
q = json.load(open(os.path.join(HERE, "quant.json")))
M, K, N = q["M"], q["K"], q["N"]
izp = int(q["input"]["zero_point"])
wzp = int(q["weight"]["zero_points"][0])

assert A.shape == (M, K) and B.shape == (K, N)

# ---- 量化对齐: uint8 - zero_point → int8 (clamp 到 [-128,127]) ----
A_s = np.clip(A.astype(np.int32) - izp, -128, 127).astype(np.int8)   # [M,K] int8
B_s = np.clip(B.astype(np.int32) - wzp, -128, 127).astype(np.int8)   # [K,N] int8

# 记录溢出 clamp 的个数 (量化契约边界证据)
a_overflow = int(np.sum((A.astype(np.int32) - izp) < -128)) + int(np.sum((A.astype(np.int32) - izp) > 127))
b_overflow = int(np.sum((B.astype(np.int32) - wzp) < -128)) + int(np.sum((B.astype(np.int32) - wzp) > 127))

# ---- INT32 黄金累加 (int8 语义, 含 bias) ----
golden = A_s.astype(np.int32) @ B_s.astype(np.int32) + bias[np.newaxis, :].astype(np.int64)
golden = golden.astype(np.int32)                                    # [M,N]

# ---- K 分块 ----
K_blocks = []
kk = 0
while kk < K:
    sz = min(K_MAX, K - kk)
    K_blocks.append(sz)
    kk += sz

# ---- M/N zero-padding ----
M_pad = ((M + ARRAY - 1) // ARRAY) * ARRAY
N_pad = ((N + ARRAY - 1) // ARRAY) * ARRAY
M_tiles, N_tiles = M_pad // ARRAY, N_pad // ARRAY

A_pad = np.zeros((M_pad, K), dtype=np.int8); A_pad[:M] = A_s
B_pad = np.zeros((K, N_pad), dtype=np.int8); B_pad[:, :N] = B_s
golden_pad = np.zeros((M_pad, N_pad), dtype=np.int32); golden_pad[:M, :N] = golden

golden_tiles = golden_pad.reshape(M_tiles, ARRAY, N_tiles, ARRAY).transpose(0, 2, 1, 3)

tiling = {
    "array_dim": ARRAY, "K_max": K_MAX,
    "M": M, "K": K, "N": N, "M_pad": M_pad, "N_pad": N_pad,
    "M_tiles": M_tiles, "N_tiles": N_tiles, "K_blocks": K_blocks,
    "total_tiles": M_tiles * N_tiles,
    "total_tasks": M_tiles * N_tiles * len(K_blocks),
    "padding": {"M_zero_rows": M_pad - M, "N_zero_cols": N_pad - N},
    "quant_align": {
        "input_zero_point": izp, "weight_zero_point": wzp,
        "contract": "uint8 - zero_point → int8 (clamp -128..127)",
        "input_clamped_elems": a_overflow, "weight_clamped_elems": b_overflow,
    },
    "bias": "最终累加一次",
}
with open(os.path.join(HERE, "tiling.json"), "w") as fh:
    json.dump(tiling, fh, indent=2, ensure_ascii=False)
np.save(os.path.join(HERE, "golden_tiles.npy"), golden_tiles)
np.save(os.path.join(HERE, "a_int8.npy"), A_s)
np.save(os.path.join(HERE, "b_int8.npy"), B_s)
np.save(os.path.join(HERE, "a_pad_int8.npy"), A_pad)
np.save(os.path.join(HERE, "b_pad_int8.npy"), B_pad)

print(f"量化对齐 + 切块完成: M={M} K={K} N={N} -> M_tiles={M_tiles} N_tiles={N_tiles} K_blocks={K_blocks}")
print(f"  契约: uint8 - zero_point(input={izp}, weight={wzp}) → int8 (clamp -128..127)")
print(f"  输入 clamp {a_overflow} 元素, 权重 clamp {b_overflow} 元素 (量化契约边界)")
print(f"  总 tile={M_tiles*N_tiles}, 总任务={tiling['total_tasks']}")
print(f"  golden_tiles 形状: {golden_tiles.shape} (INT32)")
print(f"  输出: tiling.json, golden_tiles.npy, a_int8.npy, b_int8.npy, a_pad_int8.npy, b_pad_int8.npy")
