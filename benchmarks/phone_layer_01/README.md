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
python3 benchmarks/phone_layer_01/conversion.py       # 量化对齐 + 切块 + K 分块 + golden
make sim_phone_layer TILES=2                          # RTL 一致性 (2 列 tile 快速)
make sim_phone_layer                                  # RTL 一致性 (mi=0 整行 320 tile 全量)
```

## 量化契约（重要发现，W14）

MobileNetV2 是 **uint8 非对称量化**（zero_point≠128）：本层 input zp=130、weight zp=125。
减零点后值域为 input `[-130,125]`、weight `[-124,130]`，**轻微超出 signed int8 `[-128,127]`**。

而自研 RTL 输入为 `signed [7:0]`（int8）。故对齐契约定为：

```
int8 = clamp(uint8 - zero_point, -128, 127)
golden = int8(A) @ int8(B) + bias   (INT32 累加)
```

实测 clamp 边界：权重真实仅 **2 个元素**溢出（uint8 253/254 → 129/130），输入 114 个元素
是随机输入用 0..255 均匀导致的假象（真实 ReLU 激活集中在 zero_point 附近，不会到 0..129 负区）。
此契约已写入 `tiling.json.quant_align`，确保 RTL 与 golden 在同一 int8 语义下逐元素一致。

## 一致性验证结果

| 路径 | 范围 | 结果 |
|:---|:---|:---|
| Python golden（int8 语义 INT32 累加）| A[49,320]×B[320,1280] 全量 | 基准 |
| 自研 RTL（npu_top）| mi=0 整行 320 tile × K 分块[256,64] | **5120 元素 0 mismatch** |
| Gemmini 仿真 | 待测（W14 门禁最后一项）| — |
