# 04 验证计划

版本：v0.1（草案） | 日期：2026-10-29 | 状态：P0 用例 V01–V12 随实现推进逐步点亮

## 1. 验证结构

```text
Testplan -> 定向/约束随机用例 -> Driver -> DUT
                     |                     |
                     v                     v
                Python Golden         Monitor / SVA
                     \                     /
                      +---- Scoreboard ---+
                                |
                       回归日志 / 覆盖报告
```

- 参考模型：`verification/golden_model.py`（纯 Python 整数，精确比对，无浮点容差）。
- TB 框架：cocotb（Python）+ Icarus；mac 另有 Verilator C++ TB 交叉验证。
- 每次回归记录：随机种子、输入矩阵、DUT git commit、命令、失败波形路径。

## 2. P0 测试矩阵（V01–V12）

| ID | 场景 | 重点检查 | 状态 |
|:---|:---|:---|:---|
| V01 | 零矩阵、单位矩阵 | 数据通路与初始累加清零 | 阵列级已覆盖（tb_systolic: test_zero_matrix/test_directed_identity） |
| V02 | 全正、全负、混合符号 | signed 乘法/符号扩展 | 已通过（MAC 级 + 阵列随机含全范围符号） |
| V03 | −128、127 边界组合 | 数值边界和乘积位宽 | 已通过（MAC 级，tb_mac.cpp 与 tb_mac.py 双验证） |
| V04 | K=1、2、N/2、N-1 部分归约 | 归约长度与排空时序 | 阵列级已覆盖（tb_systolic: test_partial_k）；K=16/64/256 待 controller 支持 |
| V05 | 行列边界块（零填充） | padding 不产生额外有效输出 | 待建（W4-W6 顶层） |
| V06 | 随机矩阵，固定种子集合 | 数据相关性和累加正确性 | 阵列级已跑（N=4/8，各 20 对，种子 2024） |
| V07 | 输入暂停/输出反压 | 数据稳定与全局同步停顿 | 待建（依赖 W5 停顿语义决策，见 docs/03 §1） |
| V08 | FIFO 空、满、同时读写 | 丢失/重复/溢出及指针回绕 | 已通过（含回绕用例 test_write_read_wrap） |
| V09 | 连续任务 | 旧状态泄漏、busy/done 时序 | 阵列级已覆盖累加语义（test_back_to_back）；busy/done 待顶层 |
| V10 | LOAD/COMPUTE 时复位 | 复位与状态恢复 | 阵列级已覆盖（test_mid_reset）；FIFO 已有中途复位 |
| V11 | 非法配置与 busy 时 start | 设计定义的拒绝/响应行为 | 待建（W5-W6 顶层） |
| V12 | 回归故障注入（独立分支） | Scoreboard/SVA 是否能捕获错误 | 待建 |

补充：en 门控专项已覆盖——en=0 且数据非零时不累加（tb_systolic: test_en_gating 全程非零垃圾数据；test_partial_k 的窗口外垃圾数据段双保险；test_en_asym 覆盖 A/B 单通道有效的不对称组合）。

## 3. 验收指标（目标，非当前实测）

- P0 场景全部通过；每个关键配置 ≥100 个可复现随机种子。
- 功能覆盖 bins 全部命中，目标覆盖率 ≥95%（无原生 covergroup 时用脚本覆盖矩阵替代并写明口径）。
- 关键断言零未解释失败。
- 每个发现的 Bug 有“触发用例—波形—修复 commit—回归”闭环记录。

## 4. 已完成的验证记录

- 周练习：MAC 定向测试（C++ Verilator TB 与 cocotb TB 交叉验证通过）。
- 周练习：4×4/8×8 阵列黄金向量随机比对通过（`tb/tb_systolic.py`）。
- 周练习：FIFO 空/满/同时读写测试通过（`tb/tb_fifo.py`）。
