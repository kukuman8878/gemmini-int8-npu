// =============================================================
// pe_16_64 : pe 的非默认参数实例 (A_WIDTH=16, ACC_WIDTH=64)
//   仅用于验证参数组合路径 (tb_pe.py), 不参与阵列综合
// =============================================================
module pe_16_64 (
    input  wire clk,
    input  wire rst_n,
    input  wire signed [15:0] a_in,
    input  wire signed [15:0] b_in,
    input  wire en_a,
    input  wire en_b,
    output wire signed [15:0] a_out,
    output wire signed [15:0] b_out,
    output wire en_a_out,
    output wire en_b_out,
    output wire signed [63:0] acc
);

pe #(.A_WIDTH(16), .ACC_WIDTH(64)) u_pe (
    .clk      (clk),
    .rst_n    (rst_n),
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

endmodule
