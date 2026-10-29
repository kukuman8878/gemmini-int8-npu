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
| skew 归属 | 左/上边界错位由 `input_skew.sv` **或** 测试驱动完成，二者只能取其一 | 已定契约；当前实现（周练习 TB）由驱动端完成，W4 迁移到 `input_skew.sv` |
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

### 2.2 pe.sv（已实现，已通过阵列级测试）

```systemverilog
module pe (
  input  wire clk, rst_n,
  input  wire signed [7:0] a_in, b_in,
  input  wire en_a, en_b,
  output reg  signed [7:0] a_out, b_out,
  output reg  en_a_out, en_b_out,
  output reg  signed [31:0] acc
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

### 2.4 fifo.sv（已实现，接口待收紧）

```systemverilog
module fifo #(parameter WIDTH = 8, DEPTH = 16) (
  input  wire clk, rst_n, wr_en, rd_en,
  input  wire [WIDTH-1:0] wr_data,
  output reg  [WIDTH-1:0] rd_data,
  output wire full, empty
);
```

- DEPTH 必须为 2 的幂且 ≥ 2（计数器法判满空；DEPTH=1 会使地址位宽非法，不支持）。
- 当前接口为 `wr_en/rd_en`；**W5 收紧为 valid/ready 或新增 wrapper**（TODO-决策：改内核 vs 加 adapter）。

## 3. 顶层握手契约（npu_top，W6 目标，草案）

| 信号 | 方向 | 语义 | 状态 |
|:---|:---|:---|:---|
| `cfg_valid/cfg_ready` | in/out | 携带 K 与 tile ID；仅 `valid&&ready` 拍生效 | 草案 |
| `in_valid/in_ready` | in/out | 携带 A/B 边界向量；仅 `valid&&ready` 拍消耗一个逻辑拍 | 草案 |
| `out_valid/out_ready` | out/in | 携带完整 4×4 INT32 结果；`valid&&!ready` 期间 `out_data` 必须保持稳定 | 草案 |
| `busy` | out | 任务开始至结果握手完成期间为 1 | 草案 |
| `done` | out | 一次结果完成握手产生的单拍脉冲 | 草案 |

**必须显式回答的语义问题（实现前逐条写死并加测试）**：

1. 复位时是否清除 FIFO？（默认：是——逻辑清空。实现上复位只清指针/计数器，存储阵列内容不清，但 empty 门控读使旧数据不可见，语义等价；FIFO 深度参数变更时不影响该结论）
2. `start`/`cfg` 在 busy 状态是否接受？（默认：拒绝或丢弃，由验证用例 V11 锁定行为）
3. 输出等待期间（out_ready=0）能否启动下一任务？（默认：不允许，单任务在途）
4. skew 由谁完成？（见 §1，W4 迁移至 input_skew.sv）
5. `out_valid` 在哪个周期置位？（默认：DRAIN 结束且结果锁存完成后；精确拍数以仿真+波形固化）

## 4. 已固化的黄金向量

```text
A = [[1, 2], [3, 4]]    B = [[5, 6], [7, 8]]
C = [[19, 22], [43, 50]]
```

用于检查索引、符号、传递延迟与累加；4×4 用例见 `verification/golden_model.py` 自检向量。
