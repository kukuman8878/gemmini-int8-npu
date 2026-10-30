# 05 PPA / STA 报告

版本：v2.0 | 日期：2026-10-30 | 状态：**Baseline + 两变体优化已实测**（8×8 扩展行待 W13）

## 1. 工具链与条件（已固定）

| 项目 | 值 |
|:---|:---|
| 综合工具 | Yosys 0.38+92（conda env `synth`，litex-hub） |
| STA 工具 | OpenSTA via OpenROAD 2.0-12381（同 env） |
| 工艺/Liberty | sky130_fd_sc_hd，`sky130_fd_sc_hd__tt_025C_1v80.lib`（tt 角，25°C，1.8V） |
| 时钟约束 | `synthesis/constraints.sdc`：clk 10ns（100MHz 目标），IO 延迟 2ns |
| 复现命令 | `run_synth.sh`（baseline）/ `run_synth_opt.sh`（CSA）/ `run_synth_cs.sh`（carry-select）；PDK/conda 路径可用 CONDA_BASE/PDK_DIR 覆盖 |

**口径说明**：
- yosys 不支持非压缩数组端口 → 综合视图（打包端口）与原 RTL 由等价性验证保证：`make sim_equiv`（baseline 综合视图）、`make sim_equiv_opt`（CSA）、`make sim_equiv_cs`（carry-select）。
- yosys 内置 `sta` 为玩具版 → 时序由 OpenSTA 读取 yosys 映射后网表；时钟网络理想（无 CTS/布局），报告为**综合后（pre-layout）**。
- 约束由 sta.tcl 消费 `synthesis/constraints.sdc`（单一来源）；input delay 排除 clk/rst_n（异步复位不挂输入延迟）。
- 综合视图 synth_view/* 为手写打包端口副本：修改 rtl/ 必须同步更新（文件头提醒 + `make sim_equiv*` 验证）。
- 可达频率由 STA 扫描确定（固定 netlist，收紧 CLK_NS 至 slack 过零），见 §4。

## 2. Baseline 实测结果（4×4 OS，npu_top）

| 指标 | 值 | 来源 |
|:---|:---|:---|
| 面积 (cell area) | **83774.10 µm²** | `npu_top_sv_stat.rpt` |
| 单元数 | 9651 cells | 同上 |
| 最小时钟周期 | **7.32 ns**（worst slack 2.68 @10ns；STA 数据到达时间 7.06ns） | `npu_top_sv_sta_full.rpt` |
| 可达频率 | ~137 MHz | §4 扫描 |
| 关键路径组成 | PE 累加器 32 位进位链（`acc <= acc + a*b`，maj3/xor3 全加器链） | 同上 |

## 3. 结果表（W10 实测）

| 方案 | 面积 (µm²) | WNS @10ns | 最小时钟周期 | 可达频率 | 完成周期 (K=256) | 总延迟 (K=256) | 说明 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| Baseline (`pe`) | 83774.10 | 2.68 | 7.32 ns | ~137 MHz | 264 | 1932 ns | 累加器 32 位进位链 |
| CSA (`pe_opt`+`npu_top_opt`) | 125964.56 | 3.87 | 6.13 ns | ~163 MHz | 265 | 1624 ns | carry-save 累加 + 输出流水 1 级 |
| carry-select (`pe_cs`+`npu_top_cs`) | 83467.55 | 3.10 | 6.90 ns | ~145 MHz | 264 | 1822 ns | 累加器 16+16 进位选择 |

**周期口径**（`make sim_bench` 实测，`tb/tb_bench.py`）：FSM 内部周期 = load(K) + drain(2N-1=7) + output(1) = K+8 = 264（三变体相同，controller 一致）。**完成周期 = 外部可见输出完成的拍数**：baseline/carry-select 输出为组合（state==OUT 当拍可取）= 264；CSA 输出经 1 级流水寄存器（out_valid 打拍），外部取到结果晚 1 拍 = 265（`sim_bench` 对 npu_top_opt 实测 FSM 264，外部可见 265）。

**总延迟 = 完成周期 × 最小时钟周期**，比较同一 workload（K=256 单 tile）最终执行时间。

**CSA 输出流水相位说明**：`npu_top_opt` 的 out_c/out_valid/done 三信号同步打拍 1 级；`busy` 未打拍（= state!=IDLE）。故 done 脉冲相对 baseline 晚 1 拍，且 done 期间 busy 已为 0。单拍性质保持，按外部握手对齐后契约成立；下游若依赖 done 沿需知此 1 拍偏移。

## 4. 可达频率扫描（baseline）

固定 netlist、仅收紧 CLK_NS，逐点 OpenSTA 读 worst slack：

| CLK_NS | 10.0 | 8.0 | 7.0 | 6.0 | 5.0 |
|:---|:---|:---|:---|:---|:---|
| worst slack | 2.68 | 0.68 | -0.32 | -1.32 | -2.32 |

固定网表下 slack = period − arrival 为线性（slack 每周期-1ns → arrival 恒定 7.32ns），过零点 ~7.3ns → 可达 ~137 MHz。变体可达频率由各自最小时钟周期反推（CSA 6.13→163MHz、carry-select 6.90→145MHz），未再逐点扫描。

## 5. 优化结论（W10）

**主结论**：4×4 OS 阵列的**固有瓶颈是 32 位累加器进位链**（最小时钟周期 ~7.3ns）。尝试两种优化：

1. **carry-save 累加器（CSA）**：把 32 位加法从每拍累加环移出（累加环 ~1ns），改为输出阶段一次合并。最小时钟周期降至 **6.13ns（-16%）**，可达 163MHz。代价：面积 +50%（carry 双寄存器 512ff + 输出寄存器 512ff + 16 个 full 32bit 合并加法器），且需输出流水化（外部可见输出 +1 拍）。**频率 +19%，面积 +50%，总延迟 -16%** —— 频率换面积，性价比偏低。

2. **carry-select 累加器**：纯组合拆分（16+16 进位选择），最小时钟周期 6.90ns（-6%），面积 -0.4%，周期不变。**收益微小** —— 证明 abc 已对 32bit+16bit 累加做了 carry-select 类优化，手动重写无额外空间。

**诚实结论**：单级 PE 乘加路径在该工艺/库下已接近组合优化极限；进一步提速需**输出合并加法器流水化（2 级）**或**更激进加法器结构（CLA/并行前缀）**，属后续 P1。本批次不宣称"提升 X%"，仅记录实测取舍。

## 6. 实验规则

- 比较使用同一工艺库、约束、工具版本、优化级别（§1 固定）。
- baseline 与各变体保留 git commit；一键脚本 `run_synth*.sh`。
- 优化结论同时考虑频率、周期、面积与最终执行时间；不预设优化成功。
