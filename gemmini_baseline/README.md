# Gemmini 官方基线记录

## 仓库与版本

| 项目 | 值 |
|:---|:---|
| 本地路径 | `../gemmini-ref`（clone 自 https://github.com/ucb-bar/gemmini） |
| Gemmini commit | `8c3f9923a44a2fe2c7930587be297d6d4f8c09ca`（2025-09-01，PR #392 merge） |
| CHIPYARD.hash | `e02074414158c85059c1dcb231ff2f8941254b9a`（Chipyard 对应 commit，尚未 clone） |
| 子模块 | gemmini-rocc-tests / libgemmini / onnxruntime-riscv（未拉取） |

## 构建计划（W11，未执行）

```shell
cd ../gemmini-ref/chipyard        # 待 clone 到 CHIPYARD.hash 指定 commit
./build-setup.sh
source env.sh
cd ../gemmini-ref
make -C software/libgemmini install
```

仿真入口（以固定版本 README 为准）：

```shell
cd chipyard/sims/verilator
make CONFIG=GemminiRocketConfig
```

## 实验记录

- 待执行：官方矩阵乘测试 + WS/OS 对照（用例 B01–B06 见 `docs/06_gemmini_comparison.md`）。
- 每次实验记录：命令、PASS 结果、周期/访存统计、口径说明。
