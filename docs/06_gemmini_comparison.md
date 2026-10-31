# 06 Gemmini 对照实验记录

版本：v1.1 | 日期：2026-10-31 | 状态：**官方基线测试 PASS + WS/OS 周期对照实测完成**

## 1. 官方工程版本

| 项目 | 值 |
|:---|:---|
| 仓库 | `../gemmini-ref`（clone 自 https://github.com/ucb-bar/gemmini） |
| Gemmini commit | `8c3f9923a44a2fe2c7930587be297d6d4f8c09ca`（2025-09-01，PR #392 merge） |
| Chipyard commit | `e02074414158c85059c1dcb231ff2f8941254b9a`（CHIPYARD.hash，已 clone 至 `../chipyard`） |
| 子模块 | gemmini（置入 `chipyard/generators/gemmini`，同 commit）、rocket-chip、hardfloat、testchipip 等全部 init |

## 2. 构建环境（已固定）

| 项目 | 值 |
|:---|:---|
| RISC-V 工具链 | riscv64-unknown-elf-gcc 13.2.0（conda env `.conda-env/riscv-tools`） |
| Verilator | 5.022（conda-forge） |
| Java | openjdk 20（conda env） |
| firtool (CIRCT) | 1.75.0（llvm/circt release 预编译二进制） |
| 硬件配置 | `GemminiRocketConfig`（`gemmini.DefaultGemminiConfig`，INT8，默认 16×16 阵列） |

**构建命令**：
```shell
cd chipyard && git checkout e0207441...
git submodule update --init generators/gemmini && cd generators/gemmini && git checkout 8c3f9923...
./build-setup.sh riscv-tools --skip-ctags --skip-precompile --skip-firesim --skip-marshal --skip-circt --skip-clean
source env.sh
make -C generators/gemmini/software/libgemmini install
cd generators/gemmini/software/gemmini-rocc-tests && ./build.sh
cd sims/verilator && make CONFIG=GemminiRocketConfig
```

**构建过程中踩的 3 个坑（已修复，记录复现）**：
1. **conda-lock 环境 Python 3.15 缺 `sre_parse`**：`build-setup.sh` 创建临时 `.conda-lock-env` 时未 pin Python，
   conda 装了 3.15，`conda-lock` 依赖的 poetry/lark 在 3.13+ 移除 `sre_parse` 导致 step 1 失败。
   修复：`scripts/build-setup.sh` 第 170 行加 `python=3.11`。
2. **`firtool: command not found`**：`--skip-circt` 跳过了 CIRCT 安装，但 Verilator 流程 FIRRTL→Verilog 需要 firtool。
   修复：`tools/install-circt` 下载 `circt-full-static-linux-x64.tar.gz`（firtool-1.75.0）到 `.conda-env/riscv-tools/bin`。
3. **Verilator 仿真 stack 偏小**：运行需 `ulimit -s 16384`。

## 3. 官方基线测试结果

| 测试 | 二进制 | 结果 | 耗时 | 说明 |
|:---|:---|:---|:---|:---|
| mvin/mvout 数据搬运 | `mvin_mvout-baremetal` | **PASS** | ~1 min | 数据搬运指令 |
| OS 矩阵乘 | `matmul_os-baremetal` | **PASS** | ~30 min | OUTPUT_STATIONARY，DIM=16，N=2，多组 activation/shift/preload 组合 |
| WS 矩阵乘 | `matmul_ws-baremetal` | **PASS** | ~50 min | WEIGHT_STATIONARY 对照 |

> PASS 判据：测试用 `assert` + `is_equal` 逐元素比对硬件结果与 golden，失败会打印矩阵 dump 并 `exit(1)`；
> `$finish` 正常退出即全对。完整输出保留在 `logs/gemmini/`。

## 4. WS/OS 周期对照（实测）

用官方 `tiled_matmul_os` / `tiled_matmul_ws`（`read_cycles()` = `rdcycle` CSR），同一 64×64×64 矩阵
（`MAT_DIM_I=J=K=64`，baremetal 默认），`CHECK_RESULT=1` 逐元素比对硬件 vs CPU golden（均 `$finish` 正常退出）：

| 数据流 | 周期 (cycles) | 有效 MAC | 理论峰值 MAC/cycle | 理想周期 | 端到端效率 |
|:---|:---|:---|:---|:---|:---|
| OS（输出静止）| **3550** | 64³ = 262144 | 16×16 = 256 | 1024 | **28.8%** |
| WS（权重静止）| **2268** | 262144 | 256 | 1024 | **45.1%** |

**口径（重要）**：`tiled_matmul_os/ws` 的 `start=read_cycles()` 在 `tiled_matmul_auto(...)` 之前、`end` 在其后，
而 `tiled_matmul_auto` 内部包含 `gemmini_config` + `mvin` A/B/D + `compute` + `mvout` C + `fence` 全流程。
故周期 = **端到端矩阵乘全程**（含数据搬运、配置、fence），**不是**纯阵列计算周期。表中"端到端效率"
= 有效 MAC ÷ (PE数 × 端到端周期)，反映含搬运与配置开销的整体效率，**低于**纯阵列利用率（后者需用
Gemmini performance counter 单独测 compute active cycle，本批未做）。

**结论**：WS 周期为 OS 的 63.9%（2268/3550，少 36%），即 **WS 比 OS 快 56%**（加速比 1.565×）。
原因（不单一归因）：(a) WS 权重预加载后输入流式处理，避免 OS 的 A/B 斜排 skew 填充与输出静止的
启动/排空开销；(b) `tiled_matmul_auto` 对 WS 启用 double-buffering；(c) 两者 mvin/mvout 调度不同
（OS 一次搬入后算、WS 逐 tile 交错）。端到端差距相当部分来自搬运/双缓冲调度，非纯阵列 skew。
与自研 4×4 子系统的比较见 §6。

## 5. 结果表（实测）

| 用例 | 数据流 | 周期 | 访存量 | 端到端效率 | 备注 |
|:---|:---|:---|:---|:---|:---|
| 64×64×64 | OS | 3550 | — | 28.8% | 16×16 阵列，INT8，端到端含搬运 |
| 64×64×64 | WS | 2268 | — | 45.1% | 16×16 阵列，INT8，端到端含搬运 |

## 6. 自研 4×4 OS 子系统 vs Gemmini 完整系统（口径说明）

两者**层次不同**，不把原始数值做等价芯片对比：

| 维度 | 自研 4×4 子系统 | Gemmini（GemminiRocketConfig） |
|:---|:---|:---|
| 阵列规模 | 4×4 = 16 PE | 16×16 = 256 PE |
| 层次 | 计算子系统（npu_top + controller + skew）| 完整 SoC（Rocket core + Gemmini + Scratchpad + DMA/ROB） |
| 存储 | 无片上存储（数据由测试端逐拍喂入）| 256KB Scratchpad + Accumulator |
| 数据流 | 仅 OS | OS/WS 运行时可选 |
| 可比较口径 | 单 tile 周期公式 `K+2N-1+1`、PPA（sky130 实测）| 阵列内部周期（本节）、利用率 |

**结论**：自研子系统的贡献在**自研 RTL + 验证闭环 + PPA 证据链**（docs/05），Gemmini 的贡献在
**OS/WS 架构对照**（本节：WS 端到端效率 45.1% vs OS 28.8%，量化了数据流差异）。二者不叠加成"性能对比"。
