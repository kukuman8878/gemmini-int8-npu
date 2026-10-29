# 06 Gemmini 对照实验记录（模板）

版本：v0.1 | 日期：2026-10-29 | 状态：**源码已 clone，仿真未跑（W11）**

## 1. 官方工程版本

| 项目 | 值 |
|:---|:---|
| 仓库 | `../gemmini-ref`（clone 自 https://github.com/ucb-bar/gemmini） |
| Gemmini commit | `8c3f9923a44a2fe2c7930587be297d6d4f8c09ca`（2025-09-01，PR #392 merge） |
| CHIPYARD.hash | `e02074414158c85059c1dcb231ff2f8941254b9a`（Chipyard 子模块**尚未 clone**） |
| 子模块 | gemmini-rocc-tests / libgemmini / onnxruntime-riscv（未拉取） |
| 构建环境 | 待记录（build-setup.sh 版本、工具链） |

## 2. 官方基线任务（计划）

1. 固定 commit → `cd chipyard/sims/verilator && make CONFIG=GemminiRocketConfig`（实际命令以固定版本 README 为准）。
2. 官方矩阵乘测试 PASS，保留命令与日志。
3. WS/OS 对照：相同矩阵形状、数据类型、精度、正确性标准，比较周期、访存、利用率。
4. 编写“自研 4×4 OS 子系统 vs Gemmini 完整系统”的口径说明。

## 3. 基准矩阵（计划集合，非已测结果）

| 用例 | M×K×N | 测试目的 |
|:---|:---|:---|
| B01 | 4×4×4 | 小尺寸与阵列启动开销 |
| B02 | 16×16×16 | 标准方阵 |
| B03 | 32×32×32 | 规模放大 |
| B04 | 64×64×64 | 较大 GEMM |
| B05 | 32×16×8 | 非方阵 |
| B06 | 17×17×17 | 非整 tile 的利用率与 padding |

如官方 API/配置限制导致某用例不可用，记录替代用例及原因。

## 4. 结果表（待测）

| 用例 | 数据流 | 周期 | 访存量 | 利用率 | 备注 |
|:---|:---|:---|:---|:---|:---|
| 待测 | 待测 | 待测 | 待测 | 待测 | 待测 |
