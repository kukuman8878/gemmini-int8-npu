# 10 最终交付报告（W16）

版本：v1.0 | 日期：2026-11-01 | 状态：W13–W16 完成

## 1. 三套结果，严禁混用

| 类别 | 指标 | 结论边界 |
|:---|:---|:---|
| 手机测量 | 真实延迟 median/p90、后端、设备状态 | 是 Android 设备真实推理时间，**不是** Gemmini/芯片时延 |
| RTL / Gemmini 仿真 | 逻辑周期、结果一致性 | 周期是硬件逻辑节拍，**不是**墙钟耗时 |
| EDA 估计 | 面积、关键路径、可达频率 | pre-layout 估计，**不是**布局后/流片数据 |

## 2. 实验汇总表

| 编号 | 负载 M×K×N | 执行路径 | 延迟 / 周期 | 准确性 | 证据 |
|:---|:---|:---|:---|:---|:---|
| PHONE-01 | 模型整体 (224×224 输入) | 小米 10 CPU (XNNPACK, 4线程) | **9.16 ms** (median, 3组×110 runs) | 基准 | `reports/mobile/` |
| OP-01 | 49×320×1280 (真实 1×1 Conv) | Python Golden (int8 语义 INT32 累加) | 参考值 | 基准 | `benchmarks/phone_layer_01/` |
| RTL-01 | 同 OP-01 | 自研 4×4 RTL (npu_top) | 5120 元素 | **0 mismatch** (INT32 exact) | `logs/` |
| GEM-01 | 同 OP-01 (N=16 子集) | Gemmini 16×16 (tiled_matmul OS) | 784 元素 | **0 mismatch** | `logs/gemmini/` |
| PPA-01 | 同一 RTL 配置 | 基线 vs 优化 (sky130) | 见下表 | 回归通过 | `synthesis/reports/` |

## 3. PPA 汇总（sky130 tt_025C_1v80，10ns@100MHz，同约束）

| 方案 | 面积 µm² | WNS | 最小时钟周期 | 可达频率 |
|:---|:---|:---|:---|:---|
| Baseline | 83774.10 | 2.68 | 7.32 ns | ~137 MHz |
| CSA + 输出流水1级 | 125964.56 | 3.87 | 6.13 ns | ~163 MHz |
| carry-select | 83467.55 | 3.10 | 6.90 ns | ~145 MHz |
| CSA + 输出流水2级 (W15) | 134373.88 | 2.22 | 7.78 ns | ~128 MHz (负收益) |

## 4. 一页验收 Checklist（对应 §8.1）

- [x] 手机上明确版本同一 INT8 模型重复运行，保留 benchmark 结果（MobileNetV2 `f08d447c...`，3 组稳定 9.16ms）
- [x] 记录真实后端（CPU XNNPACK；GPU delegate 未编译进工具，NPU 未测——记录而非猜测）
- [x] 提取至少一层真实 1×1 卷积（Cin=320→Cout=1280，35 层中选 K 最大）
- [x] 固定 A/B/bias、zero_point(130/125)、scale、布局(NHWC)、模型 hash
- [x] Python 黄金 vs 自研 RTL INT32 逐元素一致（5120 元素 0 mismatch）
- [x] 至少一个真实层 tile 在 Gemmini 仿真完成（N=16 子集，784 元素 0 mismatch）
- [x] 随机回归 + 断言 + 覆盖率结果，未覆盖项有解释（coverage_model 28/28 + 2 豁免）
- [x] baseline/optimized 源码 + 同约束综合/STA + 公平 PPA（4 方案对照，含负收益）
- [x] README 区分手机实测 / RTL 仿真 / EDA 估计
- [x] 5–8 分钟演示能说清个人贡献、真实数据、验证过程与取舍（`scripts/final_demo.sh`）

## 5. 三岗位证据包（对应 §10）

| 岗位 | 核心展示 | 深追问准备 |
|:---|:---|:---|
| 前端设计 | 自研 PE/阵列/FIFO/FSM + 4 方案 PPA（含负收益根因） | 关键路径、流水化、阻塞/非阻塞、时序闭合 |
| 验证 | Testplan→Scoreboard/SVA→覆盖闭环（coverpoint/cross）| 随机种子、覆盖率盲区、假绿检测、复位/背压边界 |
| NPU 架构 | 真实 1×1 Conv→GEMM 映射、WS/OS、利用率与 PPA | 量化布局、访存 vs 计算、tiling、端侧负载特性 |
