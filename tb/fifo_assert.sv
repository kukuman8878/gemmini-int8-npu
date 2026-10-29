// =============================================================
// fifo_assert : fifo 的 SVA 断言包装 (仅验证用, Verilator --assert)
//   A2 满态禁写/空态禁读协议一致性
// =============================================================
module fifo_assert #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
) (
    input  wire clk,
    input  wire rst_n,
    input  wire wr_valid,
    output wire wr_ready,
    input  wire [WIDTH-1:0] wr_data,
    output wire rd_valid,
    input  wire rd_ready,
    output wire [WIDTH-1:0] rd_data,
    output wire full,
    output wire empty
);

fifo #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_fifo (
    .clk      (clk),
    .rst_n    (rst_n),
    .wr_valid (wr_valid),
    .wr_ready (wr_ready),
    .wr_data  (wr_data),
    .rd_valid (rd_valid),
    .rd_ready (rd_ready),
    .rd_data  (rd_data),
    .full     (full),
    .empty    (empty)
);

// A2: 满态禁写 / 空态禁读 (协议一致性, 可捕获 ready/valid 输出破坏)
assert property (@(posedge clk) disable iff (!rst_n) (full  |-> !wr_ready));
assert property (@(posedge clk) disable iff (!rst_n) (empty |-> !rd_valid));
assert property (@(posedge clk) disable iff (!rst_n) ((wr_valid && wr_ready) |-> !full));
assert property (@(posedge clk) disable iff (!rst_n) ((rd_valid && rd_ready) |-> !empty));

// A2b: 复位释放后为空 (释放沿无合法写为前提, 避免误约束合法行为)
assert property (@(posedge clk) disable iff (!rst_n)
    ($rose(rst_n) && !(wr_valid && wr_ready)) |=> empty);

endmodule
