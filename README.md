# gemmini-int8-npu

基于 Gemmini 的可配置 INT8 脉动阵列加速器：数字 IC 前端设计 + 验证 + PPA 优化 + Gemmini 架构对照。

> 项目目标与验收标准见 `../Gemmini_数字IC三方向项目目标与验收文档.md`（V1.0 基线）。
> 本仓库只记录**已完成、可复现**的工作；所有性能数字均来自工具报告，未完成项以 TODO/待测标注。

## 一句话定义

参考 Gemmini 的 PE 与 OS/WS 数据流，**独立用 SystemVerilog 从零实现**可综合、可验证、可分析的 signed INT8
脉动阵列计算子系统（A/B INT8、乘积 INT16、累加 INT32、K=1…256），并以官方 Gemmini/Chipyard 环境做
WS/OS 架构对照实验。全历史 32 个 commit 可查。

## 当前状态（2026-10-31，主线 W1–W11 全部完成）

| 维度 | 状态 |
|:---|:---|
| RTL 主线 | mac → pe → input_skew → 阵列 → fifo → controller → npu_top 全闭环（`rtl/`） |
| 优化变体 | carry-save（`pe_opt`/`npu_top_opt`）、carry-select（`pe_cs`/`npu_top_cs`），均等价性验证通过 |
| 验证闭环 | 17 个回归目标全绿；Golden/Scoreboard/SVA/覆盖矩阵/故障注入/agent 突变审核；15 条缺陷闭环 |
| 综合/STA | yosys + OpenSTA（sky130_fd_sc_hd，tt 角），baseline + 2 变体实测报告（`docs/05`） |
| Gemmini 对照 | 官方基线测试 PASS + WS/OS 周期对照实测（`docs/06`，环境见 `../chipyard`） |

## 环境与版本

| 工具 | 版本 | 用途 |
|:---|:---|:---|
| Verilator | 5.052（默认 conda）| lint / C++ TB / SVA 后端 |
| Icarus Verilog | 12.0 | cocotb 仿真后端 |
| cocotb | 2.1.0 | Python TB |
| Python / NumPy | 3.14.6 / 2.5.2 | Golden model |
| Yosys | 0.38+92（conda env `synth`）| 综合 |
| OpenROAD / OpenSTA | 2.0-12381（同 env）| 静态时序分析 |
| sky130 PDK | open_pdks.sky130a（`synth` env）| 标准单元库（tt_025C_1v80） |
| Chipyard / Gemmini | `e0207441` / `8c3f9923`（`../chipyard`）| 官方基线对照 |

## 目录结构

```text
rtl/              RTL（mac/pe/input_skew/systolic_array/fifo/controller/npu_top + 优化变体 *_opt/*_cs）
tb/               cocotb TB + Verilator C++ TB + 等价性 wrapper + SVA 断言
verification/     golden_model.py、scoreboard、随机回归、覆盖矩阵
synthesis/        SDC、flow 脚本（synth/sta/run_*）、synth_view、reports
gemmini_baseline/ 官方 Gemmini 版本记录、README
benchmark/        workload、comparison.csv
docs/             01 需求 / 02 架构 / 03 接口 / 04 验证 / 05 PPA / 06 对照 / 07 限制 / 08 Bug 日志
scripts/          故障注入等辅助脚本
logs/             回归日志 + Gemmini 官方测试输出
```

## 快速开始（一键验证）

```bash
make lint             # Verilator lint 全部 RTL + synth_view + 等价 wrapper（0 警告）
make regress          # 全部 17 个仿真目标（回归日志到 logs/）
make sim_top          # npu_top 端到端（基本/K随机/暂停/反压/连续任务/中途复位/非法配置）
make sim_top_sva      # SVA 断言（Verilator --assert 后端；另有 sim_pe_sva/sim_fifo_sva）
make sim_equiv        # 综合视图 vs 原 RTL 逐拍等价（另有 sim_equiv_opt/sim_equiv_cs）
make sim_bench        # 周期测量（load=K/drain=2N-1/out=1）
make fault_inject     # V12 故障注入（验证回归能捕获缺陷）
make synth            # baseline 综合+STA（sky130）；变体见 run_synth_opt.sh/run_synth_cs.sh
```

## 测试覆盖（V01–V12，`docs/04`）

- **功能**：MAC 边界（±128×±128 等 245 组穷举）、PE 转发/累加/门控、阵列 K=1…256（含 K>N 部分归约）、
  FIFO 空/满/同时读写/回绕、controller 非法配置/busy 拒绝/同拍 cfg+start、端到端反压/连续任务/中途复位。
- **断言**：A1 背压稳定 / A2 FIFO 满写空读 / A3 busy-state 一致 / A4 复位合法态 / A5 无效拍不改 acc /
  A6 DRAIN 段进度（A1/A2 经变异验证可触发）。
- **等价性**：综合视图 vs RTL 逐拍、两优化变体 vs baseline 结果值（均 `$fatal` 门禁 + 突变验证）。
- **闭环**：15 条真实缺陷"触发用例—波形—根因—修复 commit—回归"（`docs/08`）。

## 综合 / PPA 结果（`docs/05`，sky130 tt_025C_1v80，10ns@100MHz）

| 方案 | 面积 (µm²) | WNS @10ns | 最小时钟周期 | 可达频率 | 完成周期(K=256) |
|:---|:---|:---|:---|:---|:---|
| Baseline | 83774.10 | 2.68 | 7.32 ns | ~137 MHz | 264 |
| carry-save | 125964.56 | 3.87 | 6.13 ns | ~163 MHz | 265 |
| carry-select | 83467.55 | 3.10 | 6.90 ns | ~145 MHz | 264 |

结论：32 位累加器进位链为固有瓶颈；carry-save 频率 +19% 但面积 +50%，carry-select 近零收益。

## Gemmini 对照（`docs/06`）

官方基线 PASS（`mvin_mvout`/`matmul_os`/`matmul_ws`）；WS/OS 周期对照（64×64×64，端到端含搬运）：
OS 3550 cycles（28.8%）、WS 2268 cycles（45.1%）——WS 快 56%。自研 4×4 子系统与 Gemmini 完整系统
**层次不同不直接对比**，口径说明见 `docs/06 §6`。

## 个人贡献边界

- 自研部分：`rtl/` 全部 RTL、`tb/`、`verification/`、`synthesis/`、`benchmark/`、`docs/`、`scripts/`。
- 外部参考：`../gemmini-ref`、`../chipyard`（Gemmini/Chipyard 官方源码，仅用于架构对照与基线实验，不冒充自研）。

## 复现说明

1. `git log` 查看 32 个 commit 的设计迭代记录；每个 RTL 文件头注释写明来源与验证状态。
2. 综合/STA：`source .../synth conda env` 后 `make synth`（或 `synthesis/flow/run_synth*.sh`），PDK 路径可 `CONDA_BASE/PDK_DIR` 覆盖。
3. Gemmini 基线：环境在 `../chipyard`（commit `e0207441`），构建命令与踩坑见 `docs/06 §2`。
4. 所有性能数字以 `synthesis/reports/` 与 `logs/` 为准，不预填、不估算。
