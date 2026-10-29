# 02 架构说明

版本：v0.1（草案） | 日期：2026-10-29 | 状态：随实现迭代更新

## 1. 顶层结构（目标）

```text
                     测试程序 / 主机驱动
                (配置 tile / 提供 A、B / 切块)
                           |
               cfg / data valid-ready / status
                           v
     +------------------------------------------------+
     |                npu_top.sv                      |
     |                                                |
     |  +---------------+       +------------------+  |
     |  | controller FSM|------>| 输入调度 / Skew   |  |
     |  +---------------+       +------------------+  |
     |           |                       |             |
     |  +---------------+                v             |
     |  | FIFO / 缓冲区 |-------> 4 x 4 PE 阵列 (OS)   |
     |  +---------------+         A ->  /  B v        |
     |                                  C 局部累加    |
     |                                       |          |
     |                              结果锁存/输出握手 |
     +---------------------------------------|----------+
                                              v
                                  C tile (INT32) / done
```

## 2. 数据流：OS 模式（已定）

- 每个 PE 保存其负责的 C[i,j] 累加值。
- A 由左向右、B 由上向下，每拍前进一格。
- 为使 A[i,k] 与 B[k,j] 在 PE(i,j) 同拍相遇：
  - 左边界 A 的第 i 行延迟 i 拍（索引从 0 开始）；
  - 上边界 B 的第 j 列延迟 j 拍。
- 数据有效时才累加（en_a && en_b）；停顿期间整个阵列同步保持状态（逻辑拍不前进）。

## 3. 已有实现（周练习导入 + W2-W4 硬化）

| 文件 | 内容 | 备注 |
|:---|:---|:---|
| `rtl/mac.sv` | en 使能的乘累加 | W2 参数化 A_WIDTH/ACC_WIDTH |
| `rtl/pe.sv` | a/b 各寄存 1 拍转发 + 局部累加 | W3 参数化 |
| `rtl/input_skew.sv` | A 行/B 列移位链错位 (delay 1+i) | W4 新增 |
| `rtl/systolic_array.sv` | 参数化 N×N 阵列 | generate 网格，行优先拍平输出 |
| `rtl/systolic_4x4.sv` / `rtl/systolic_8x8.sv` | 4×4 / 8×8 薄包装 | 4×4 为 P0，8×8 为 P1 |
| `rtl/fifo.sv` | 同步 FIFO（WIDTH×DEPTH） | 当前为 wr_en/rd_en 接口，valid/ready 化待 W5 |

## 4. 待建模块

| 文件 | 职责 | 计划周 |
|:---|:---|:---|
| `rtl/controller.sv` | IDLE/LOAD/COMPUTE/DRAIN/OUTPUT FSM | W5 |
| `rtl/npu_top.sv` | 系统连接、全局握手、结果输出 | W6 |

（`rtl/input_skew.sv` 已于 W4 完成，见 §2。）

## 5. 与 Gemmini 的关系

- 对照对象：Gemmini `MeshWithDelays`（两级层次：Tile 内组合 PE + Tile 间流水寄存器）与
  WS/OS 双数据流。
- 本项目自研部分为轻量 4×4 子系统；对照实验在 `../gemmini-ref` 固定 commit 上单独进行。
- 层次不同（无 Scratchpad/DMA/ROB），不把两者原始数值做等价芯片对比。
