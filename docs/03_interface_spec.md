# 03 接口规范

版本：v0.2（草案，随实现固化） | 日期：2026-10-29 | 状态：**部分条目为待决策（TODO-决策），实现前必须收敛**

> 规则：本文件未固化的语义禁止直接在 RTL 中“顺手实现”；每次修改语义必须同步更新本文件并跑回归。

## 1. 全局约定

| 项目 | 约定 | 状态 |
|:---|:---|:---|
| 复位 | 现有导入模块为**异步低有效**（`negedge rst_n`）；计划统一为**同步高有效**（`posedge rst`） | **TODO-决策**（W2/W3 收紧时定死，全仓库统一） |
| 时钟 | 单时钟域 `clk`，无 CDC | 已定 |
| 位宽 | A/B = signed 8bit；乘积 = signed 16bit；累加 = signed 32bit | 已定 |
| K 范围 | 1…256（单 tile 归约长度） | 已定 |
| skew 归属 | 左/上边界错位由 `input_skew.sv` **或** 测试驱动完成，二者只能取其一 | 已定契约；当前实现（周练习 TB）由驱动端完成，W4 迁移到 `input_skew.sv` |
| 无效数据 | 无效拍（en=0）不得更新累加器；停顿期间逻辑拍不前进 | 已定 |

## 2. 模块端口（当前导入基线）

### 2.1 mac.sv（已实现，已通过定向测试）

```systemverilog
module mac (
  input  wire clk, rst_n, en,
  input  wire signed [7:0]  a, b,
  input  wire signed [31:0] acc_in,
  output reg  signed [31:0] acc_out
);
```

- 语义：`en=1` → `acc_out <= acc_in + a*b`；`en=0` → 保持（`acc_out <= acc_in`）。
- 所有运算 signed；乘积 16bit 自动符号扩展至 32bit。

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

### 2.3 systolic_array.sv（已实现，参数化 N×N）

```systemverilog
module systolic #(parameter N = 4) (
  input  wire clk, rst_n,
  input  wire signed [7:0] a_row [0:N-1], b_col [0:N-1],
  input  wire        en_a  [0:N-1], en_b  [0:N-1],
  output wire signed [31:0] c_flat [0:N*N-1]   // 行优先拍平
);
```

- 边界注入：`a_row[i]`/`en_a[i]` 接第 i 行左边界；`b_col[j]`/`en_b[j]` 接第 j 列上边界。
- 时序：N×N×N 单 tile 满速流水时，结果在 `3N-2` 拍后全部就绪（4×4 为 10 拍）。
- skew 由外部（驱动或 input_skew）完成：A 第 i 行延迟 i 拍、B 第 j 列延迟 j 拍。

### 2.4 fifo.sv（已实现，接口待收紧）

```systemverilog
module sync_fifo #(parameter WIDTH = 8, DEPTH = 16) (
  input  wire clk, rst_n, wr_en, rd_en,
  input  wire [WIDTH-1:0] wr_data,
  output reg  [WIDTH-1:0] rd_data,
  output wire full, empty
);
```

- DEPTH 必须为 2 的幂（计数器法判满空）。
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

1. 复位时是否清除 FIFO？（默认：是）
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
