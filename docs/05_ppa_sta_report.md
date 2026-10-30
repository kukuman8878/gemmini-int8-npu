# 05 PPA / STA 报告（W9 基线）

版本：v1.0 | 日期：2026-10-30 | 状态：**Baseline 已实测**（优化/扩展行待 W10/W13）

## 1. 工具链与条件（已固定）

| 项目 | 值 |
|:---|:---|
| 综合工具 | Yosys 0.38+92（conda env `synth`，litex-hub） |
| STA 工具 | OpenSTA via OpenROAD 2.0-12381（同 env） |
| 工艺/Liberty | sky130_fd_sc_hd，`sky130_fd_sc_hd__tt_025C_1v80.lib`（tt 角，25°C，1.8V） |
| 时钟约束 | `synthesis/constraints.sdc`：clk 10ns（100MHz 目标），IO 延迟 2ns |
| 综合入口 | `synthesis/flow/synth_view/npu_top_sv.sv`（打包端口综合视图，与原 RTL 逐拍等价——`make sim_equiv` 验证） |
| 复现命令 | `synthesis/flow/run_synth.sh`（一键 yosys + OpenSTA; PDK/conda 路径可用 CONDA_BASE/PDK_DIR 环境覆盖） |

**口径说明**：
- yosys 不支持非压缩数组端口 → 综合视图（打包端口）与原 RTL 由 `tb/equiv_wrap.sv` 逐拍等价性验证（tb_top 全量用例，0 mismatch）。
- yosys 内置 `sta` 为玩具版（无法识别映射后单元）→ 时序由 OpenSTA 读取 yosys 映射后网表完成；时钟网络理想（无 CTS/布局）。
- 约束由 sta.tcl 消费 `synthesis/constraints.sdc`（单一来源）；input delay 排除 clk/rst_n（异步复位不挂输入延迟）。
- 综合视图 synth_view/* 为手写打包端口副本：修改 rtl/ 必须同步更新（文件头有提醒，`make sim_equiv` 验证等价性）。
- 异步复位 `rst_n` 的 recovery check 由 OpenSTA 一并覆盖。
- 报告为**综合后（pre-layout）**时序，非布局后。

## 2. Baseline 实测结果（4×4 OS，npu_top）

| 指标 | 值 | 来源 |
|:---|:---|:---|
| 面积 (cell area) | **83774.10 µm²** | `synthesis/reports/npu_top_sv_stat.rpt` |
| 单元数 | 9651 cells | 同上 |
| 关键路径 (WNS) | **worst slack 2.68 ns** @ 10ns 周期 | `synthesis/reports/npu_top_sv_sta_full.rpt` |
| 目标/可达频率 | 100MHz 目标收敛；slack 2.68ns → 理论可进一步降周期（未实测上限） | 同上 |
| 关键路径组成 | PE 累加器 32 位进位链（maj3/xor3/o21ai 全加器链，~7.06ns 数据路径 (OpenSTA 实测 arrival)） | 同上 |

## 3. 结果表

| 方案 | 阵列 | 面积 | WNS | 目标/可达频率 | 完成周期 | 总延迟 | 说明 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| Baseline | 4×4 OS | 83774.10 µm² | 2.68 ns @10ns | 100MHz 收敛 | K+2N-1+握手 | 待测 | sky130 hd, tt 角 |
| Optimized | 4×4 OS | 待测 | 待测 | 待测 | 待测 | 待测 | W10 计划 |
| Scale-up | 8×8 OS | 待测 | 待测 | 待测 | 待测 | 待测 | W13 计划 |

## 4. 实验规则

- 比较必须使用同一工艺库、同一约束、同一工具版本、同一优化级别（本页 §1 条件固定）。
- 保留 baseline 与 optimized 的 git commit，一键脚本 `synthesis/flow/run_synth.sh`。
- 优化结论同时考虑频率、周期、面积；不预设“提升 X%”。
