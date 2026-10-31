# 09 项目总结报告（W12 交付）

版本：v1.0 | 日期：2026-10-31 | 状态：主线 W1–W11 完成

## 1. 一句话总结

独立用 SystemVerilog 实现了一个可综合、可验证、可分析的 signed INT8 脉动阵列计算子系统
（4×4 OS，K=1…256，INT32 累加），配套完整验证闭环（Golden/Scoreboard/SVA/覆盖矩阵/故障注入/
agent 突变审核）、真实综合/STA 报告（sky130，baseline + 2 变体 PPA 对比），并跑通官方 Gemmini
基线、完成 WS/OS 周期对照。33 个 commit，15 条缺陷闭环，17 个回归目标全绿。

## 2. 三种岗位版本的项目讲述

### 2.1 数字 IC 前端设计

**标题**：可配置 INT8 脉动阵列计算子系统 RTL 设计与 PPA 优化。

**讲述**：自底向上 mac→pe→input_skew→阵列→fifo→controller→npu_top，每层先锁接口契约再写 RTL。
关键决策：OS 数据流（skew 只在 input_skew 一处）；acc_clr 放 IDLE 态持续置位（清零≠排空）；
done 寄存器单拍脉冲；同拍 cfg+start 一律无效。综合后关键路径是 PE 的 32 位累加器进位链
（7.32ns），尝试 carry-save（6.13ns，+50% 面积）与 carry-select（6.90ns，近零收益）两种优化，
诚实记录频率-面积-周期取舍。

**核心证据**：`rtl/` 全部 RTL + `docs/03` 契约 + `docs/05` PPA 报告 + `docs/08` 15 条 bug。
**追问准备**：非阻塞赋值、位宽溢出（Icarus `$signed(a*b)` 截 8bit）、valid/ready 反压、寄存器面积开销、时序收敛。

### 2.2 数字 IC 验证

**标题**：INT8 NPU 计算子系统功能验证平台与覆盖率闭环。

**讲述**：Python 整数 golden（与补码硬件独立实现）逐元素精确比对；Scoreboard 组件化；
cocotb+Icarus 日常回归 + cocotb+Verilator `--assert` 跑 SVA（A1–A6）；覆盖矩阵 V01–V12 逐 bin 核对；
故障注入 `/tmp` 变异副本 + agent 突变审核闭环。抓到 3 个"假绿"测试（回归脚本退出码、en 门控 0×0=0、
FIFO 稳态分布盲区）和等价性门禁"无牙齿"（Icarus `$error` 非致命），全部以"突变→测试必须红"证明修复。

**核心证据**：`verification/`、`tb/`、`docs/04`、`docs/08`、17 目标回归日志。
**追问准备**：参考模型独立性、覆盖率盲区、断言触发、随机种子复现、DUT/TB 竞争冒险、检查器自身注入验证。

### 2.3 NPU 架构

**标题**：面向 INT8 GEMM 的脉动阵列设计与 WS/OS 数据流分析。

**讲述**：OS 阵列（输出静止，A 左→右、B 上→下，边界 skew 错位）实现 4×4 tile，K>N 时流式部分归约，
tile 切块放测试端。周期实测 load=K、drain=2N-1、output=1（总 K+8）。Gemmini 官方基线（16×16 阵列）
WS/OS 对照：64×64×64 端到端 OS 3550 cycles（28.8%）、WS 2268 cycles（45.1%）——WS 快 56%，
量化了数据流差异（含搬运/双缓冲调度，不单一归因 skew）。

**核心证据**：`docs/02` 架构、`docs/06` 对照、`benchmark/`、Gemmini 官方日志。
**追问准备**：算术强度、阵列空泡、tile/padding、OS/WS 复用对象、载入/排空开销、存储带宽瓶颈、PPA 权衡。

## 3. 简历 bullet（按岗位取用）

**前端设计**：
- 独立用 SystemVerilog 实现 4×4 OS 脉动阵列 INT8 GEMM 子系统（MAC/PE/skew/阵列/FIFO/FSM/顶层），K=1…256，INT32 累加，可综合无锁存器。
- 完成 yosys+OpenSTA（sky130）综合/STA，实测关键路径 7.32ns、面积 83774 µm²；设计 carry-save 与 carry-select 两变体并做 PPA 对比（频率 +19% vs 面积 +50% 的取舍）。

**验证**：
- 搭建 cocotb+Icarus 验证平台（Python 整数 golden + Scoreboard + 覆盖矩阵 V01–V12 + SVA A1–A6 + 故障注入），17 个回归目标全绿。
- 引入 agent 突变审核闭环，捕获 3 个"假绿"测试与等价性门禁缺陷（Icarus `$error` 非致命），15 条 bug 全闭环。

**架构**：
- 跑通官方 Gemmini/Chipyard 基线（RISC-V 工具链 + Verilator），完成 WS/OS 周期对照（64×64×64：WS 2268 vs OS 3550 cycles，WS 快 56%），并写清与自研子系统的层次口径。

**通用能力**：SystemVerilog / Python / cocotb / Verilator / Yosys / OpenSTA / Makefile / git（33 commit 迭代）。

## 4. 口径红线（面试/简历一致遵守）

- 仿真墙钟时间 ≠ 硬件周期数 ≠ 芯片真实时间；周期只以波形/`rdcycle` 为准。
- 综合后（pre-layout）时序 ≠ 布局后；无活动率/功耗库不报功耗。
- 所有"提升 X%"必须同一库/约束/工具版本对比；未完成项写"规划"而非"成果"。
