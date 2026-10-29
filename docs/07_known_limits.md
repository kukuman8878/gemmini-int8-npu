# 07 已知限制

版本：v0.1 | 日期：2026-10-29 | 状态：随实现更新

## 当前限制

1. RTL 为导入基线（异步低复位、en 标志传递、FIFO 为 wr/rd 接口），尚未按 `03_interface_spec.md` 统一握手契约。
2. 尚无 input_skew/controller/npu_top；skew 当前由测试驱动完成。
3. 单 tile 仅支持 4×4（8×8 已有实例但未纳入顶层）；大矩阵切块在测试端。
4. 无 bias/ReLU/量化；输出为精确 INT32。
5. 无功耗结论（缺活动率与功耗库）。
6. 仿真墙钟时间不代表硬件周期；未做布局后 STA。
7. Gemmini 官方基线未构建运行（Chipyard 构建较重，见风险表）。

## 风险与缓解（摘自项目验收文档 §11）

- Verilog 基础薄弱 → MAC→PE→4×4 顺序推进，不跳级。
- Chisel/SV 混用 → 自研核心用 SV，Gemmini 对照单独建立。
- UVM 工具兼容 → 先 cocotb 跑通，后评估 UVM。
- 只改开源参数 → 强制保留原创 RTL/TB/脚本与设计记录。
