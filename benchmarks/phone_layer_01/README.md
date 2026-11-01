# W14 算子选择与抽取（phone_layer_01）

## 算子选择策略（2026-11-01 定稿）

按"**大 K 更适配 4×4 阵列**"的思路，从 MobileNetV2 的 35 个 1×1 pointwise 层中选 K（=Cin，归约长度）
较大者，以体现阵列吞吐（K 越大，`2N-1` 拍 skew/drain 开销占比越低，利用率越高）。

| 优先级 | 层 (Cin→Cout) | K | M (空间) | N | 说明 |
|:---|:---|:---|:---|:---|:---|
| **首选** | 320 → 1280 | 320 | 49 (7×7) | 1280 | 最后 1×1 conv（global avg pool 前），K 大 |
| 备选 | 576 → 160 | 576 | 196 (14×14) | 160 | K 最大，M 更大（tile 更多） |
| 简化 | 96 → 576 | 96 | 196 | 576 | K=96 单 tile 不超 256，验证数据量适中 |

**首选层**：`Cin=320 → Cout=1280`，K=320 > 阵列 K 上限 256 → 需 K 分块（320 = 256 + 64），
正好展示 F7 的"K 分块由测试端驱动"能力。M=49（需 13 个 4×4 行 tile）、N=1280（320 个列 tile）。

> 全 35 层枚举见 `benchmarks/phone_layer_01/layers_enum.txt`（由 `extract.py --list` 生成）。

## 测试包结构

```text
benchmarks/phone_layer_01/
  manifest.json           # model_hash, op_name, dims, dtype, layout
  input_a_int8.npy        # A[M,K] (M=49, K=320) 真实输入
  weight_b_int8.npy       # B[K,N] (K=320, N=1280) 权重
  bias_int32.npy          # N=1280 偏置
  quant.json              # zero_point/scale/round/saturate
  golden_acc_int32.npy    # CPU 整数黄金值 (INT32 累加)
  conversion.py           # conv→GEMM + K 分块 + tiling
  extract.py              # 从 .tflite 抽取本层张量 (本文件来源)
```

## 抽取命令

```bash
python3 benchmarks/phone_layer_01/extract.py          # 抽取首选层 → npy + quant.json
python3 benchmarks/phone_layer_01/extract.py --list   # 枚举全部 pointwise 层
```
