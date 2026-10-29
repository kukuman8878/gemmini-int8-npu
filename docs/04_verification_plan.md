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
| V04 | K=1、2、N/2、N-1 部分归约 | 归约长度与排空时序 | 阵列级已覆盖（tb_systolic: test_partial_k）；K∈{1,2,4,8,16}（含 K>N）已覆盖（tb_skew: test_random_k）；K=64/256 待 controller 支持 |
| V05 | 行列边界块（零填充） | padding 不产生额外有效输出 | 黄金向量 2×2→4×4 零填充已覆盖（tb_skew: test_golden_2x2） |
| V06 | 随机矩阵，固定种子集合 | 数据相关性和累加正确性 | 阵列级已跑（N=4/8，各 20 对，种子 2024） |
| V07 | 输入暂停/输出反压 | 数据稳定与全局同步停顿 | 输入暂停已覆盖（controller 级 test_load_stall_and_drain + skew 级 test_en_gating）；输出反压已覆盖（test_output_handshake）；流水冻结语义待 W5+ 停顿决策 |
| V08 | FIFO 空、满、同时读写 | 丢失/重复/溢出及指针回绕 | 已通过（valid/ready 化后 7 项测试含随机握手 scoreboard） |
| V09 | 连续任务 | 旧状态泄漏、busy/done 时序 | 阵列/skew 级累加语义已覆盖；done 单拍/旧配置清除已覆盖（test_output_handshake） |
| V10 | LOAD/COMPUTE 时复位 | 复位与状态恢复 | 阵列/skew/PE 级已覆盖；controller 级复位待 W6 顶层联调 |
| V11 | 非法配置与 busy 时 start | 设计定义的拒绝/响应行为 | 已通过（tb_controller: test_illegal_cfg K=0/257/511、test_busy_reject） |
| V12 | 回归故障注入（独立分支） | Scoreboard/SVA 是否能捕获错误 | 已覆盖：`make fault_inject`（/tmp 变异副本 en 门控破坏 → 回归正确失败）+ 历轮 agent 突变验证（docs/08_bug_log.md） |

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

## 5. MAC 边界运算报告（W2）

| 类别 | 用例 | 结论 |
|:---|:---|:---|
| 基本 | 3×4、12+(-5)×6、en=0 保持 | 通过（tb_mac.py 定向 6 组 + tb_mac.cpp 交叉） |
| INT8 极值 | -128×-128=16384、127×127=16129、-128×127=-16256 | 通过，符号扩展正确 |
| 随机 | 2000 组全范围 a/b、acc ∈ ±2^20（无回绕区间） | 通过，与任意精度参考一致 |
| 穷举边界 | a,b ∈ {-128,-127,-1,0,1,126,127} × acc ∈ {INT32_MIN,-2^20,0,2^20,INT32_MAX}（245 组） | 通过，与 `mac_ref_wrap` 32 位回绕模型精确一致 |

**溢出语义结论**：累加器溢出按 ACC_WIDTH 位 2 的补码回绕，无饱和/无标志；该行为已写入 docs/03 §2.1 并被测试锁定。K=256 最坏累加幅值上界为 256×16384=2^22，正常 tile 工作不触发 32 位回绕。

## 6. PE 单模块验证报告（W3）

`tb/tb_pe.py`（cocotb，顶层 `pe`，`make sim_pe`；波形 `make sim_pe WAVES=1`）：

| 测试 | 检查点 | 结论 |
|:---|:---|:---|
| test_reset_state | 复位后 a_out/b_out/en 标志/acc 全清零 | 通过 |
| test_forwarding | a/b 与 en 标志 1 拍寄存转发（含 ±128/127/0 边界） | 通过 |
| test_accumulate | en_a=en_b=1 连续累加，与 `mac_ref_wrap` 回绕模型比对（含 -128×-128 极值） | 通过 |
| test_en_gating | (0,1)/(1,0)/(0,0) 三种无效组合且数据非零时 acc 保持 | 通过 |
| test_mid_reset | 累加中复位：acc 与转发寄存器清零 | 通过 |
| test_random | 1000 拍随机数据 + 随机 en 组合，Scoreboard 逐拍比对（含转发/标志/累加全量比对） | 通过 |

## 7. input_skew 联合验证报告（W4）

`tb/tb_skew.py`（cocotb，顶层 `skew_systolic_4x4` = input_skew + systolic_4x4，`make sim_skew`）：

| 测试 | 检查点 | 结论 |
|:---|:---|:---|
| test_golden_2x2 | 接口规范黄金向量（2×2 零填充至 4×4） | 通过 |
| test_zero | 零矩阵 tile | 通过 |
| test_en_gating | valid=0 且垃圾数据非零时不累加 | 通过 |
| test_random_k | K∈{1,2,4,8,16}（含 K>N）随机 tile 精确比对 | 通过 |
| test_back_to_back | 连续任务累加语义（不排空直接接下一任务） | 通过 |
| test_mid_reset | 呈现中途复位后只含新任务结果 | 通过 |

时序口径：K 拍呈现 + (2N-1) 拍排空；该口径经黄金模型逐元素比对验证，与 docs/03 §2.5 一致。

## 8. FIFO / controller 验证报告（W5）

**fifo**（`tb/tb_fifo.py`，`make sim_fifo`）：复位/填充排空(16)/满拒写/空拒读/同时读写/指针回绕/2000 拍随机握手（Python deque 参考模型逐拍比对）——全部通过。

**controller**（`tb/tb_controller.py`，`make sim_controller`）：复位 IDLE/配置握手与重配置/非法 K 拒绝(0/257/511)/同拍 cfg+start 无效/LOAD 计数与输入暂停/排空 2N-1 拍/输出握手与 done 单拍脉冲/旧配置清除/busy 拒绝 cfg 与 start——全部通过。

**FIFO 改内核决策**（docs/03 §2.4）：wr_en/rd_en 内核改为 valid/ready 内核（push=wr_valid&&wr_ready, pop=rd_valid&&rd_ready），设计中唯一存储流协议与顶层一致，避免 adapter 反压复杂性。

## 9. npu_top 端到端验证报告（W6，P0 门禁）

`tb/tb_top.py`（cocotb，顶层 `npu_top`，`make sim_top`）：

| 测试 | 检查点 | 结论 |
|:---|:---|:---|
| test_e2e_basic | 黄金向量 tile + 完整握手 + done 单拍 + busy | 通过 |
| test_e2e_random_k | K∈{1,2,4,8,16}（含 K>N）精确比对 | 通过 |
| test_e2e_input_pause | LOAD 中途 in_valid=0 暂停不影响结果 | 通过 |
| test_e2e_backpressure | out_ready=0 反压期间 out_valid 保持、out_c 稳定 | 通过 |
| test_e2e_back_to_back | 连续任务任务边界清零（第二任务只含 C2） | 通过 |
| test_e2e_mid_reset | 任务中途复位回 IDLE，新任务正确 | 通过 |
| test_e2e_illegal_and_stale | 非法 K 拒绝 + 旧配置失效 | 通过 |

**W6 门禁判定：P0 核心功能通过**（模块链 mac→pe→skew→阵列→fifo→controller→top 全部闭环，任务生命周期与握手机制完整验证）。

## 10. 验证平台组件（W7）

| 组件 | 位置 | 说明 |
|:---|:---|:---|
| Scoreboard | `verification/scoreboard.py` | 逐元素精确比对计分板（log 注入、失败明细、check_matrix、summary）；tb_top/tb_regression 经 `tb_common.py` 复用（聚合统计见 tb_regression）；tb_skew/tb_systolic 保留本地等价 compare |
| Driver/Monitor | `tb/tb_common.py` | npu_top 端到端共享助手（reset/cfg/start/load_slices/wait_and_read/run_task） |
| 批量随机回归 | `verification/random_regression.py` + `tb/tb_regression.py` + `make sim_top_seeded` | SEED×K{1,2,4,8,16}×PAIRS；日志记录 DUT rev/命令/种子/逐种子结果（`logs/random_regression_<rev>.json`） |
| 覆盖矩阵 | `verification/coverage_matrix.py` | V01–V12 bin 映射核对，未覆盖 bin 退出码 1 |
| 故障注入 | `scripts/fault_injection.sh` + `make fault_inject` | /tmp 变异副本（不触碰工作区），验证回归捕获缺陷 |
| Bug 追踪 | `docs/08_bug_log.md` | 13 条真实缺陷（现象/触发用例/根因/修复 commit/回归） |

**计划口径**：每个关键配置 ≥100 个可复现随机种子（`python3 verification/random_regression.py --seeds 100 --pairs 1` 可达 100 种子 × 5 K × 1 对 = 500 tile）；演示运行 5 种子 × 5 K × 2 对通过（`logs/random_regression_*.json`）。

## 11. SVA 断言闭环（W8）

Icarus 12 不支持并发 SVA（syntax error on property_spec），故断言在 **Verilator `--assert` 后端**执行（cocotb 驱动同一 TB），其余回归保持 Icarus：

| 断言 | 模块 | 属性 | 突变验证 |
|:---|:---|:---|:---|
| A1 | tb/npu_top_assert.sv | `out_valid && !out_ready \|=> $stable(out_c_packed)` | acc_clr→out_valid 变异：verilator 断言直接报告捕获 ✓ |
| A2 | tb/fifo_assert.sv | `full \|-> !wr_ready`、`empty \|-> !rd_valid`、握手前提一致性、复位为空 | wr_ready=1'b1 变异：断言报告捕获 ✓ |
| A3 | tb/npu_top_assert.sv | `busy == (state != IDLE)`、out_valid/in_ready/cfg_ready 与 busy 关系（结构/连线一致性检查） | 随 A1 变异运行无假阳性 |
| A4 | tb/npu_top_assert.sv | `$rose(rst_n) \|=> IDLE && !busy && !out_valid` | 全任务流无假阳性 |
| A5 | tb/pe_assert.sv | `(!acc_clr && !(en_a&&en_b)) \|=> acc == $past(acc)`、复位清零（释放沿无有效累加为前提） | en 门控变异：TB+断言共同覆盖，无假阳性 |
| A6 | tb/npu_top_assert.sv | **DRAIN 段内部进度**：`(state==DRAIN) \|-> ##[1:2N-1] (state==OUT)`（真 LTL，无外部握手依赖）；LOAD/OUTPUT 段进度以握手为前提，由 TB 超时机制保证 | K=256 端到端无假阳性（tb_top: test_e2e_large_k） |

**执行**：`make sim_top_sva / sim_pe_sva / sim_fifo_sva`（已纳入 regress）。断言无未解释失败；关键断言经变异验证可触发（docs/08_bug_log.md 突变总览）。
