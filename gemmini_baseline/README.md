# Gemmini 官方基线记录

## 仓库与版本

| 项目 | 值 |
|:---|:---|
| 本地路径 | `/home/kukuman/NPU/gemmini-ref`（clone 自 https://github.com/ucb-bar/gemmini） |
| Gemmini commit | `8c3f9923a44a2fe2c7930587be297d6d4f8c09ca`（2025-09-01，PR #392 merge） |
| Chipyard commit | `e02074414158c85059c1dcb231ff2f8941254b9a`（CHIPYARD.hash，clone 至 `/home/kukuman/NPU/chipyard`） |
| 子模块 | gemmini（置入 `chipyard/generators/gemmini`，同 commit）、rocket-chip、hardfloat、testchipip 等全部 init |

## 构建环境（W11 已完成）

| 项目 | 值 |
|:---|:---|
| RISC-V 工具链 | riscv64-unknown-elf-gcc 13.2.0（`.conda-env/riscv-tools`） |
| Verilator | 5.022（conda-forge） |
| Java | openjdk 20（conda env） |
| firtool (CIRCT) | 1.75.0 |
| 硬件配置 | `GemminiRocketConfig`（DefaultGemminiConfig，INT8，16×16 阵列） |

构建命令（与 `docs/06_gemmini_comparison.md §2` 一致）。构建踩坑 3 处已记录（conda-lock Python 3.15 缺 `sre_parse`、
`--skip-circt` 导致 firtool 缺失、Verilator 需 `ulimit -s 16384`）。

## 实验记录（W11 实测）

官方测试 PASS（`$finish` 正常退出，`assert`/`is_equal` 逐元素比对无失败）：

| 测试 | 结果 | 耗时 |
|:---|:---|:---|
| `mvin_mvout-baremetal` | PASS | ~1 min |
| `matmul_os-baremetal`（OS 矩阵乘）| PASS | ~30 min |
| `matmul_ws-baremetal`（WS 矩阵乘）| PASS | ~50 min |

WS/OS 周期对照（`tiled_matmul_os`/`tiled_matmul_ws`，64×64×64，`read_cycles()`，端到端含搬运）：

| 数据流 | 周期 | 端到端效率 |
|:---|:---|:---|
| OS（输出静止）| 3550 | 28.8% |
| WS（权重静止）| 2268 | 45.1% |

WS 周期为 OS 的 63.9%（少 36%），即快 56%（加速比 1.565×）。完整输出保留在 `logs/gemmini/`，
口径说明见 `docs/06_gemmini_comparison.md §4/§6`。
