# gemmini-int8-npu

基于 Gemmini 的可配置 INT8 脉动阵列加速器：数字 IC 前端设计 + 验证 + PPA 优化 + Gemmini 架构对照。

> 项目目标与验收标准见 `../Gemmini_数字IC三方向项目目标与验收文档.md`（V1.0 基线）。
> 本仓库只记录**已完成、可复现**的工作；未完成部分在文档中标注为计划（TODO/待测）。

## 一句话定义

参考 Gemmini 的 PE 与 OS/WS 数据流，独立开发可综合、可验证、可分析的 signed INT8
脉动阵列计算子系统（A、B 为 INT8，乘积 INT16，累加 INT32，K=1…256），
并以官方 Gemmini/Chipyard 环境做 WS/OS 架构对照实验。

## 当前状态（2026-10-29）

| 模块 | 状态 |
|:---|:---|
| `mac.sv` / `pe.sv` / `systolic_array.sv` / `fifo.sv` | 已从周练习导入，功能已验证，待按 `docs/03_interface_spec.md` 收紧为 valid/ready 契约 |
| `input_skew.sv` / `controller.sv` / `npu_top.sv` | 待开发（W4–W6） |
| 验证闭环（Golden/Scoreboard/SVA/回归） | 部分：cocotb + Python golden 已跑通 MAC/阵列；SVA/覆盖待建（W7–W8） |
| 综合 / STA | 待建（W9，Yosys/OpenSTA 未安装） |
| Gemmini 官方基线 | 源码已 clone 至 `../gemmini-ref`（commit 见 `gemmini_baseline/README.md`），仿真待跑（W11） |

## 环境与版本

| 工具 | 版本 | 用途 |
|:---|:---|:---|
| Verilator | 5.052 | lint / C++ TB 仿真 |
| Icarus Verilog | 12.0 | cocotb 仿真后端 |
| cocotb | 2.1.0 | Python TB |
| Python / NumPy | 3.14.6 / 2.5.2 | Golden model |
| Yosys / OpenSTA | 未安装 | W9 综合与 STA |

## 目录结构

```text
rtl/              RTL（.sv，来源与状态见文件头注释）
tb/               cocotb TB + Verilator C++ TB
verification/     golden_model.py、scoreboard、回归脚本
synthesis/        SDC、flow 脚本、reports
gemmini_baseline/ 官方 Gemmini 版本记录、configs、results
benchmark/        workload 与 comparison.csv
docs/             01 需求 / 02 架构 / 03 接口 / 04 验证计划 / 05 PPA / 06 对照 / 07 限制
scripts/          辅助脚本
```

## 快速开始

```bash
make lint          # Verilator lint 全部 RTL
make sim_mac       # cocotb: MAC 定向测试
make sim_mac_v     # Verilator C++ TB: MAC 交叉验证
make sim_fifo      # cocotb: FIFO valid/ready (随机握手 scoreboard/回绕)
make sim_controller # cocotb: controller FSM (配置/启动/暂停/排空/输出握手/done单拍)
make sim_top       # cocotb: npu_top 端到端 (基本tile/K随机/暂停/反压/连续任务/中途复位/非法配置)
make sim_skew     # cocotb: input_skew+4x4 联合 (黄金向量/K随机含K>N/门控/连续/复位)
make sim_array     # cocotb: 4x4 脉动阵列直接驱动 (定向/随机/零矩阵/en门控/部分K/连续任务/中途复位)
make sim_array8    # cocotb: 8x8 脉动阵列
make regress       # 全部 P0 仿真 + 回归日志
```

## 验证口径

- Golden model 为纯 Python 整数运算（`verification/golden_model.py`），与 DUT 逐元素精确比对，无浮点容差。
- 每次回归记录：随机种子、输入矩阵、DUT 版本（git commit）、命令与失败波形路径。
- 性能口径：仿真墙钟时间 ≠ 硬件周期数 ≠ 芯片真实时间；周期数只以波形/事务日志为准。

## 个人贡献边界

- 自研部分：`rtl/` 全部 RTL、`tb/`、`verification/`、`synthesis/`、`benchmark/`。
- 外部参考：`../gemmini-ref`（Gemmini/Chipyard 官方源码，仅用于架构对照与基线实验，不冒充自研）。

## 复现说明

1. `git log` 查看设计迭代记录；每个 RTL 文件头部注释写明来源与验证状态。
2. 所有未完成项以 TODO 标注，不预填性能数字。
