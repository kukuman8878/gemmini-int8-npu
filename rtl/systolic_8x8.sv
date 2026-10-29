// =============================================================
// systolic_8x8 : 8x8 脉动阵列 (systolic 的参数化实例, N=8)
//   64 个 PE, 22 拍 (3N-2) 完成 8x8 矩阵乘
// =============================================================
module systolic_8x8 (
    input  wire clk,
    input  wire rst_n,
    input  wire signed [7:0] a_row [0:7],
    input  wire signed [7:0] b_col [0:7],
    input  wire        en_a  [0:7],
    input  wire        en_b  [0:7],
    output wire signed [31:0] c_flat [0:63]
);

systolic_array #(.N(8)) u_sys (
    .clk    (clk),
    .rst_n  (rst_n),
    .a_row  (a_row),
    .b_col  (b_col),
    .en_a   (en_a),
    .en_b   (en_b),
    .c_flat (c_flat)
);

endmodule
