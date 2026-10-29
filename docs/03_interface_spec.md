# 03 接口规范

版本：v0.2（草案，随实现固化） | 日期：2026-10-29 | 状态：**部分条目为待决策（TODO-决策），实现前必须收敛**

> 规则：本文件未固化的语义禁止直接在 RTL 中“顺手实现”；每次修改语义必须同步更新本文件并跑回归。

## 1. 全局约定

| 项目 | 约定 | 状态 |
|:---|:---|:---|
| 复位 | 现有导入模块为**异步低有效**（`negedge rst_n`）；计划统一为**同步高有效**（`posedge rst`） | **TODO-决策**（W2/W3 收紧时定死，全仓库统一） |
| 时钟 | 单时钟域 `clk`，无 CDC | 已定 |
| 位宽 | A/B = signed 8bit；乘积 = signed 16bit；累加 = signed 32bit（默认值；mac.sv 已参数化 A_WIDTH/ACC_WIDTH） | 已定 |
| K 范围 | 1…256（单 tile 归约长度） | 已定 |
| skew 归属 | 左/上边界错位由 `input_skew.sv` 完成（设计中唯一 skew 点）；tb_systolic 直接测阵列时在驱动端斜排属测试行为 | 已定（W4 已迁移至 `input_skew.sv`） |
| 无效数据 | 无效拍（en=0）不得更新累加器 | 已定（当前 PE 实现：en=0 仅门控 acc，流水寄存器照常移位） |
| 停顿语义 | 停顿/反压期间是否冻结整条流水 | **TODO-决策**（当前 PE 不冻结流水；W5 controller 引入背压时一并定义，可选 recirculation 或时钟门控） |

## 2. 模块端口（当前导入基线）

### 2.1 mac.sv（已实现，参数化；已通过定向/随机/穷举边界测试）

```systemverilog
module mac #(
  parameter A_WIDTH   = 8,   // a/b 有符号位宽
  parameter ACC_WIDTH = 32   // 累加器有符号位宽
) (
  input  wire clk, rst_n, en,
  input  wire signed [A_WIDTH-1:0]  a, b,
  input  wire signed [ACC_WIDTH-1:0] acc_in,
  output reg  signed [ACC_WIDTH-1:0] acc_out
);
```

- 语义：`en=1` → `acc_out <= acc_in + a*b`；`en=0` → 保持（`acc_out <= acc_in`）。
- 所有运算 signed；乘积 2×A_WIDTH bit（默认参数下为 16bit）自动符号扩展至 ACC_WIDTH。
- **溢出语义（已锁定）**：ACC_WIDTH 位 2 的补码回绕，无饱和、无溢出标志；由穷举边界测试（245 组，含 INT32_MIN/MAX 累加值）与参考模型 `mac_ref_wrap` 精确锁定。

### 2.2 pe.sv（已实现，参数化；已通过单 PE 全语义测试 + 阵列级测试）

```systemverilog
module pe #(
  parameter A_WIDTH   = 8,   // a/b 有符号位宽
  parameter ACC_WIDTH = 32   // 累加器有符号位宽
) (
  input  wire clk, rst_n,
  input  wire signed [A_WIDTH-1:0] a_in, b_in,
  input  wire en_a, en_b,
  output reg  signed [A_WIDTH-1:0] a_out, b_out,
  output reg  en_a_out, en_b_out,
  output reg  signed [ACC_WIDTH-1:0] acc
);
```

- `a_out/b_out` 与 `a_in/b_in` 为 1 拍寄存转发；`en` 标志随数据同拍传递。
- `en_a && en_b` 同时有效才累加；否则 `acc` 保持。
- 累加为内联实现（未实例化 mac.sv），但语义与 mac.sv 一致：32 位 2 补码回绕。单 tile 最坏幅值上界 K×16384（K≤256 时 ≤2^22 ≪2^31），实际不会触发回绕；mac 级回绕语义由 test_exhaustive_boundary 锁定。

### 2.3 systolic_array.sv（已实现，参数化 N×N）

```systemverilog
module systolic_array #(parameter N = 4) (
  input  wire clk, rst_n,
  input  wire signed [7:0] a_row [0:N-1], b_col [0:N-1],
  input  wire        en_a  [0:N-1], en_b  [0:N-1],
  output wire signed [31:0] c_flat [0:N*N-1]   // 行优先拍平
);
```

- 边界注入：`a_row[i]`/`en_a[i]` 接第 i 行左边界；`b_col[j]`/`en_b[j]` 接第 j 列上边界。
- 时序：N×N 阵列做 N×K×N 单 tile 满速流水时（K=N），结果在 `3N-2` 拍后全部就绪（4×4 为 10 拍）；K<N 时为 `2N+K-2` 拍。
- skew 由外部（驱动或 input_skew）完成：A 第 i 行延迟 i 拍、B 第 j 列延迟 j 拍。
- 薄包装实例：`systolic_4x4`（N=4，c_ij 拍平输出）、`systolic_8x8`（N=8，c_flat 输出），无重复逻辑。

### 2.4 fifo.sv（W5 已改内核为 valid/ready，已通过随机握手测试）

```systemverilog
module fifo #(parameter WIDTH = 8, DEPTH = 16) (
  input  wire clk, rst_n,
  input  wire wr_valid, output wire wr_ready,
  input  wire [WIDTH-1:0] wr_data,
  output wire rd_valid, input  wire rd_ready,
  output reg  [WIDTH-1:0] rd_data,
  output wire full, empty
);
```

- DEPTH 必须为 2 的幂且 ≥ 2（计数器法判满空；DEPTH=1 会使地址位宽非法，不支持）。
- 协议：`push = wr_valid && wr_ready`、`pop = rd_valid && rd_ready`；`rd_valid = !empty`、`wr_ready = !full`。
- 满态可读不可写（pop 让出空间后下拍可写）；同拍读写由 cnt 计数统一处理。
- 复位：指针/计数清零（逻辑清空，存储阵列内容不清但 empty 门控读使旧数据不可见）。

### 2.5 input_skew.sv（W4 已实现，已通过联合测试）

```systemverilog
module input_skew #(parameter N = 4, A_WIDTH = 8) (
  input  wire clk, rst_n, valid,
  input  wire signed [A_WIDTH-1:0] a_vec [0:N-1],  // A 列切片 a_vec[i]=A[i][k]
  input  wire signed [A_WIDTH-1:0] b_vec [0:N-1],  // B 行切片 b_vec[j]=B[k][j]
  output wire signed [A_WIDTH-1:0] a_row [0:N-1],
  output wire en_a  [0:N-1],
  output wire signed [A_WIDTH-1:0] b_col [0:N-1],
  output wire en_b  [0:N-1]
);
```

- 每拍呈现一个归约切片（k=0…K-1）；`valid=1` 表示切片有效；无效拍数据照常进入移位链但不参与累加（en 链与数据链同深度同步门控）。
- 移位链实现：A 第 i 行延迟 1+i 拍、B 第 j 列延迟 1+j 拍（A/B 同幅偏移，相对对齐不变；输出全寄存器，便于时序收敛）。
- 时序：K 拍呈现 + (2N-1) 拍排空后 4×4 结果全部就绪（相比驱动端直灌多 1 拍流水延迟）。
- 首版无背压（valid 仅门控）；停顿语义 TODO-决策见 §1。
- 联合验证：`tb/skew_systolic_4x4.sv`（input_skew + systolic_4x4）+ `tb/tb_skew.py`。

### 2.6 controller.sv（W5 已实现，已通过 FSM 全语义测试）

```systemverilog
module controller #(parameter N = 4, K_WIDTH = 9) (
  input  wire clk, rst_n,
  input  wire cfg_valid, output wire cfg_ready,
  input  wire [K_WIDTH-1:0] cfg_k,
  input  wire start,
  input  wire in_valid, output wire in_ready, output wire in_accept,
  output wire out_valid, input  wire out_ready,
  output wire busy, output reg  done, output reg [1:0] state
);
```

- 状态机：`IDLE → LOAD(K 拍接受切片) → DRAIN(2N-1 拍) → OUTPUT(握手) → IDLE`。
- 握手：`cfg_valid/cfg_ready` 仅 IDLE 有效；`in_accept = in_valid && in_ready` 驱动 input_skew；`out_valid` 保持等待 `out_ready`。
- `done` 为寄存器输出的单拍脉冲（输出完成握手沿后一拍置位）。
- 任务完成后 `cfg_done` 清零，需重新配置才能 start（旧配置不残留）。
- 语义决策见 §3（6 条已锁定）。

## 3. 顶层握手契约（npu_top，W6 目标，草案）

| 信号 | 方向 | 语义 | 状态 |
|:---|:---|:---|:---|
| `cfg_valid/cfg_ready` | in/out | 携带 K 与 tile ID；仅 `valid&&ready` 拍生效 | 草案 |
| `in_valid/in_ready` | in/out | 携带 A/B 边界向量；仅 `valid&&ready` 拍消耗一个逻辑拍 | 草案 |
| `out_valid/out_ready` | out/in | 携带完整 4×4 INT32 结果；`valid&&!ready` 期间 `out_data` 必须保持稳定 | 草案 |
| `busy` | out | 任务开始至结果握手完成期间为 1 | 草案 |
| `done` | out | 一次结果完成握手产生的单拍脉冲 | 草案 |

**已锁定的语义决策（W5，实现前定稿，测试验证）**：

1. 复位时是否清除 FIFO？→ **是，逻辑清空**（指针/计数清零；存储阵列内容不清但 empty 门控读使旧数据不可见）。
2. `cfg`/`start` 在 busy 状态是否接受？→ **拒绝**：busy 时 `cfg_ready=0`（cfg 无效），`start` 被忽略；需先完成当前任务回到 IDLE。
3. 输出等待期间（out_ready=0）能否启动下一任务？→ **不允许**，FSM 串行：单任务在途，OUTPUT 握手完成后才回 IDLE。
4. skew 由谁完成？→ **`input_skew.sv`**（设计中唯一 skew 点，W4 已实现）。
5. `out_valid` 在哪个周期置位？→ **DRAIN 结束沿之后**（末切片接受沿起第 2N-1 个沿后进入 OUTPUT 态，`out_valid=1`），结果已稳定锁存。
6. 配置时序：`cfg` 与 `start` 不能同拍生效 → cfg 先握手，`start` 于其后任一周期生效（同拍 start 无效，需下一拍再 start；IDLE 中已有配置时同拍 cfg+start 亦无效，本拍 cfg 照常接收、start 顺延）。K 合法域 1…256，K=0 或 >256 视为非法配置被拒绝（`cfg_done` 不置位，start 无效）。

## 4. 已固化的黄金向量

```text
A = [[1, 2], [3, 4]]    B = [[5, 6], [7, 8]]
C = [[19, 22], [43, 50]]
```

用于检查索引、符号、传递延迟与累加；4×4 用例见 `verification/golden_model.py` 自检向量。
