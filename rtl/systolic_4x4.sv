// =============================================================
// systolic_4x4 : 4x4 脉动阵列 (systolic_array 的 N=4 薄包装)
//   输入: A 矩阵按行斜排从左进, B 矩阵按列斜排从上进 (skew 由外部完成)
//   输出: 每个 PE 的 acc = C[i][j] (拍平的 c_ij 端口, 便于波形与测试访问)
// =============================================================
module systolic_4x4 (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,
    input  wire signed [7:0] a_row [0:3],   // 4 行的左端输入
    input  wire signed [7:0] b_col [0:3],   // 4 列的上端输入
    input  wire        en_a  [0:3],         // 每行数据有效标志 (随A斜流)
    input  wire        en_b  [0:3],         // 每列数据有效标志 (随B斜流)
    // 16 个 PE 的累加结果 (拍平接口, 便于测试环境访问)
    output wire signed [31:0] c_00, c_01, c_02, c_03,
                              c_10, c_11, c_12, c_13,
                              c_20, c_21, c_22, c_23,
                              c_30, c_31, c_32, c_33
);

wire signed [31:0] c_flat [0:15];

systolic_array #(.N(4)) u_sys (
    .clk    (clk),
    .rst_n  (rst_n),
    .acc_clr (acc_clr),
    .a_row  (a_row),
    .b_col  (b_col),
    .en_a   (en_a),
    .en_b   (en_b),
    .c_flat (c_flat)
);

assign c_00 = c_flat[0];  assign c_01 = c_flat[1];  assign c_02 = c_flat[2];  assign c_03 = c_flat[3];
assign c_10 = c_flat[4];  assign c_11 = c_flat[5];  assign c_12 = c_flat[6];  assign c_13 = c_flat[7];
assign c_20 = c_flat[8];  assign c_21 = c_flat[9];  assign c_22 = c_flat[10]; assign c_23 = c_flat[11];
assign c_30 = c_flat[12]; assign c_31 = c_flat[13]; assign c_32 = c_flat[14]; assign c_33 = c_flat[15];

endmodule
