// =============================================================
// pe_assert : pe 的 SVA 断言包装 (仅验证用, Verilator --assert)
//   A5 无效拍不改累加器 / A5b 复位后清零
// =============================================================
module pe_assert #(
    parameter A_WIDTH   = 8,
    parameter ACC_WIDTH = 32
) (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,
    input  wire signed [A_WIDTH-1:0] a_in,
    input  wire signed [A_WIDTH-1:0] b_in,
    input  wire en_a,
    input  wire en_b,
    output wire signed [A_WIDTH-1:0] a_out,
    output wire signed [A_WIDTH-1:0] b_out,
    output wire en_a_out,
    output wire en_b_out,
    output wire signed [ACC_WIDTH-1:0] acc
);

pe #(.A_WIDTH(A_WIDTH), .ACC_WIDTH(ACC_WIDTH)) u_pe (
    .clk      (clk),
    .rst_n    (rst_n),
    .acc_clr  (acc_clr),
    .a_in     (a_in),
    .b_in     (b_in),
    .en_a     (en_a),
    .en_b     (en_b),
    .a_out    (a_out),
    .b_out    (b_out),
    .en_a_out (en_a_out),
    .en_b_out (en_b_out),
    .acc      (acc)
);

// A5: 无清零且非双通道有效时, 累加器必须保持不变
assert property (@(posedge clk) disable iff (!rst_n)
    (!acc_clr && !(en_a && en_b)) |=> (acc == $past(acc)));

// A5b: 复位释放后累加器清零
assert property (@(posedge clk) disable iff (!rst_n)
    $rose(rst_n) |=> (acc == {ACC_WIDTH{1'b0}}));

endmodule
