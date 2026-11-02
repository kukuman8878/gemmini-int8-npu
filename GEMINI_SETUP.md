# 进阶教程：搭建 Gemmini 官方对照环境

> **先读完主教程 [`TUTORIAL.md`](TUTORIAL.md) 再来看这篇。**
> 这篇讲的是"怎么把官方 Gemmini 跑起来，跟我们的电路做对比"。
> **提前警告**：这一步很重——要下载几十 GB 的工具和代码、编译可能要 1~2 小时。如果你的目标是先搞懂我们的自研电路，这篇可以跳过。

---

## 0. 为什么要做"Gemmini 对照"？

我们的电路是自己写的脉动阵列。但"自研"不能空口说——需要跟一个**权威的参照物**对比，证明：

1. 我们对"脉动阵列怎么算矩阵乘法"的理解是对的
2. 同样的矩阵乘法，我们的电路算出的结果和官方 Gemmini 一模一样

**Gemmini** 是加州大学伯克利分校开源的 AI 加速器（用 Chisel 语言写的，Chisel 是另一种"描述电路的语言"）。我们把它当作"标准答案"来对照。

> 重要：Gemmini 是**别人写的开源项目**，我们只是拿来跑对照实验，**绝不冒充是自己写的**。这点在项目文档里反复声明。

---

## 1. 你需要什么

| 要求 | 说明 |
|---|---|
| 磁盘空间 | **至少 60 GB 空闲**（Chipyard + 工具链 + 编译产物很占地方） |
| 时间 | 下载 + 编译约 1~2 小时（取决于网速） |
| 网络 | 能访问 GitHub 和 Google 的存储（国内可能需要代理） |
| conda | 装工具链用 |

---

## 2. 构建步骤

### 2.1 下载 Chipyard（Gemmini 运行的环境）

Gemmini 不能单独跑，它要装在 **Chipyard**（伯克利的 SoC 开发框架）里面。

```bash
git clone https://github.com/ucb-bar/chipyard.git
cd chipyard
# 固定到我们验证过的版本（重要！不同版本命令可能不一样）
git checkout e02074414158c85059c1dcb231ff2f8941254b9a
```

**这一步在干嘛**：把 Chipyard 下载下来，并"退回到"一个我们测试过能用的旧版本（锁定版本，保证可复现）。

### 2.2 把 Gemmini 装进去

```bash
git submodule update --init generators/gemmini
cd generators/gemmini
git checkout 8c3f9923a44a2fe2c7930587be297d6d4f8c09ca
cd ../..
```

**这一步在干嘛**：Chipyard 里的 `generators/gemmini` 是一个"子模块"（指向另一个 git 仓库的指针）。这两行把它下载下来，并固定到我们验证过的版本。

### 2.3 安装工具链（最耗时的一步）

```bash
./build-setup.sh riscv-tools --skip-ctags --skip-precompile --skip-firesim --skip-marshal --skip-circt --skip-clean
source env.sh
```

**这一步在干嘛**：
- 用 conda 装 RISC-V 编译工具链（RISC-V 是 Chipyard 里 CPU 的指令集）
- 下载 Chipyard 的所有子模块
- 编译 Spike（一个软件仿真器）

`--skip-*` 是跳过我们用不到的东西（FPGA 仿真、FireSim 等），省时间。

**可能卡住的地方（3 个已知坑）**，见下一节。

### 2.4 编译 Gemmini 的软件（测试程序）

```bash
make -C generators/gemmini/software/libgemmini install
cd generators/gemmini/software/gemmini-rocc-tests
./build.sh
```

**这一步在干嘛**：把 Gemmini 自带的测试程序（矩阵乘法、卷积等）编译成能在仿真器里跑的二进制。

### 2.5 编译 Verilator 仿真器（也很耗时）

```bash
cd ../../../sims/verilator
make CONFIG=GemminiRocketConfig
```

**这一步在干嘛**：用 Verilator 把整个 SoC（RISC-V CPU + Gemmini）编译成一个可执行文件（相当于一个"软件版的芯片"）。首次编译可能要 30~60 分钟。

**成功后**：目录下会出现 `simulator-chipyard.harness-GemminiRocketConfig` 这个可执行文件。

---

## 3. 三个已知的坑（踩过，照做就能避开）

### 坑 1：conda 环境 Python 版本太新导致报错

**现象**：`build-setup.sh` 在第一步就报错 `ModuleNotFoundError: No module named 'sre_parse'`。

**原因**：conda 自动装了 Python 3.15，太新，某个工具不兼容。

**解决**：编辑 `scripts/build-setup.sh`，找到创建 conda-lock 环境的那行（约 170 行），在末尾加上 `python=3.11`：

```bash
# 原来：
conda create -y -p $CONDA_LOCK_ENV_PATH -c conda-forge $(grep "conda-lock" ...) &&
# 改成（末尾加 python=3.11）：
conda create -y -p $CONDA_LOCK_ENV_PATH -c conda-forge $(grep "conda-lock" ...) python=3.11 &&
```

然后重新跑 `build-setup.sh`。

### 坑 2：报 `firtool: command not found`

**现象**：编译 Verilator 时报 `firtool: 未找到命令`。

**原因**：`firtool` 是把 Chisel 代码翻译成 Verilog 的工具，我们用了 `--skip-circt` 跳过了它的安装。

**解决**：手动补装：

```bash
source env.sh
git submodule update --init tools/install-circt
./tools/install-circt/bin/download-release-or-nightly-circt.sh \
  -f circt-full-static-linux-x64.tar.gz \
  -i $CONDA_PREFIX/riscv-tools \
  -v version-file -x conda-reqs/circt.json -g null
```

### 坑 3：跑仿真报 stack 太小

**现象**：运行仿真器时报 `%Warning: System has stack size 8192 kb which may be too small`。

**解决**：运行前加大栈大小：

```bash
ulimit -s 16384
```

---

## 4. 跑官方矩阵乘法测试

```bash
cd chipyard/sims/verilator
source ../../env.sh
ulimit -s 16384
./simulator-chipyard.harness-GemminiRocketConfig \
  ../../generators/gemmini/software/gemmini-rocc-tests/build/bareMetalC/matmul_os-baremetal
```

**这一步在干嘛**：让"软件版的芯片"运行一个矩阵乘法测试程序。

**应该看到**（等约 30 分钟，Verilator 仿真很慢）：
- 最后输出 `Verilog $finish`，**没有**打印任何 `MISMATCH` 或矩阵错误

这就是"通过"——Gemmini 官方测试算出的矩阵乘法和它的标准答案一致。

---

## 5. 结果对照（我们项目里已跑出来的数据）

我们用官方的 `tiled_matmul_os` / `tiled_matmul_ws` 测试，测了两种数据流的周期数（64×64×64 矩阵）：

| 数据流 | 周期数 | 含义 |
|---|---|---|
| OS（输出静止） | 3550 | 我们自研电路用的就是这种 |
| WS（权重静止） | 2268 | 另一种数据流 |

WS 比 OS 快 56%。这就是"数据流选择"对性能的影响——**这是架构层面的取舍，也正是我们项目里"为什么选 OS"这个问题的答案依据**。

详细的对照数据和分析见 `docs/06_gemmini_comparison.md`。

---

## 6. 常见问题

**Q：这一步太复杂了，能跳过吗？**
A：能。Gemmini 对照是"进阶"内容，用来证明我们的自研电路跟权威实现一致。如果你只想搞懂自研电路，`TUTORIAL.md` 的 1~4 步就够了。

**Q：下载 Chipyard 特别慢/失败**
A：国内访问 GitHub 和 Google 存储可能需要代理。可以配置 git 代理后重试。

**Q：编译了几个小时还没好，正常吗？**
A：正常。首次编译要编译整个 SoC，30~60 分钟是常态。耐心等，别中断。
