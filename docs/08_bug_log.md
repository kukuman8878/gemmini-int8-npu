# 08 Bug 追踪记录

> 记录本项目中真实发现与修复的设计/TB 缺陷。每条含：现象—触发用例—根因—修复 commit—回归确认。
> 对应验证计划要求："每个发现的 Bug 有触发用例—波形—修复 commit—回归闭环记录"。

## 设计缺陷

| # | 现象 | 触发用例 | 根因 | 修复 | 回归 |
|:--|:--|:--|:--|:--|:--|
| B1 | 已配置状态下同拍 cfg+start 会启动任务（用旧配置） | test_reconfig_same_cycle（新增） | controller start 条件未屏蔽同拍 cfg（决策 6 角落） | `496106f` | controller 8/8 |
| B2 | done 脉宽随 out_ready 保持时间变化，非严格单拍 | test_output_handshake（沿后采样暴露） | done 组合输出而非寄存器脉冲 | `36c6f62` | controller 8/8 |

## 测试基座缺陷（假绿/采样错误）

| # | 现象 | 触发用例 | 根因 | 修复 | 回归 |
|:--|:--|:--|:--|:--|:--|
| B3 | 仿真失败仍打印 REGRESSION PASS | 故障注入实测复现 | `cmd \| tee` 管道退出码取 tee 恒 0 | `47491bc`（去管道 + 失败即退出） | 故障注入退出码 2 |
| B4 | tb_systolic test_en_gating 假绿 | 突变 en 门控后仍 PASS | en=0 拍数据恒为 0，0×0=0 无法暴露 | `a651fb1`（全程非零 garbage） | 强突变 if(1'b1) 被捕获 |
| B5 | test_partial_k 挂 IndexError | 首次运行即失败 | golden matmul_ref 只支持方阵；B 切片取错方向（`B[:,:K]` 应为 `B[:K,:]`） | `47491bc` | array/array8 全绿 |
| B6 | tb_controller 第 K 拍少计数导致假失败 | test_load_stall_and_drain | 沿后采样 in_ready（接受沿后已降 0） | `36c6f62`（沿前采样 in_accept） | controller 7/7 |
| B7 | tb_fifo 随机握手无法发现 wr_ready 破坏 | 突变 wr_ready=1'b1 仍 PASS | 随机稳态偏空 + 模型无占用率校验 | `496106f`（push 偏多分布 + 占用率交叉校验 + 矛盾断言） | 同突变现被捕获 |
| B8 | 单拍 acc_clr 在流水残留时清零不干净 | test_acc_clr_midflow 首版设计 | 清零 ≠ 排空；残留 en=1 数据继续累加 | `ef4398b`（清零覆盖整个排空窗口的正确用法测试） | array 10/10 |

## 环境/工程缺陷

| # | 现象 | 触发用例 | 根因 | 修复 | 回归 |
|:--|:--|:--|:--|:--|:--|
| B9 | make sim 无限递归执行自定义 regression | 首次 make sim_mac 挂死 | cocotb Makefile.inc 的 sim 依赖同名 regression 目标，被本地目标覆盖 | `47491bc`（改名 regress） | 全绿 |
| B10 | 源文件变更后共用 sim_build 不重编译 | 模块重命名后报 root handle 找不到 | 各 sim 目标共用 sim_build/sim.vvp，时间戳未失效 | `47491bc`（每目标独立 SIM_BUILD） | 全绿 |
| B11 | sim_pe VERILOG_SOURCES 为空 | 首次 make sim_pe 编译失败 | Makefile 漏定义 PE_SRCS | `ee204ed` | pe 8/8 |
| B12 | icarus 报 "Can not assign non-array to array" | 首次 make sim_skew 编译失败 | wrapper 中 `wire [0:3] en_a` 是压缩数组而非非压缩端口 | `68abd1a` | skew 6/6 |
| B13 | en 门控单通道破坏无法分辨 | 复审突变 &&→en_a 未被任何测试区分 | en_a/en_b 恒同值驱动 | `54ac24a`（test_en_asym 双相位独立驱动） | 两方向突变各被唯一相位捕获 |

## 突变验证总览（V12 证据链）

历轮 agent 审核的突变注入：regress 假绿（B3）、en 门控 3 种突变、skew 抽头取消错位、acc_clr 接线去除、FIFO ready/valid 破坏、mac 运算符号反转、PE 转发破坏、controller 计数破坏等——均被对应测试捕获后恢复，工作区全程干净。永久化入口：`scripts/fault_injection.sh`（`make fault_inject`）。
