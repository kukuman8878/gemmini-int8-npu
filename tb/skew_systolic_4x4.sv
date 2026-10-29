// =============================================================
// skew_systolic_4x4 : input_skew + systolic_4x4 测试包装 (仅测试用)
//   外部接口: 每拍列/行切片 (a_vec/b_vec) + valid
// =============================================================
module skew_systolic_4x4 (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,
    input  wire valid,
    input  wire signed [7:0] a_vec [0:3],
    input  wire signed [7:0] b_vec [0:3],
    output wire signed [31:0] c_00, c_01, c_02, c_03,
                              c_10, c_11, c_12, c_13,
                              c_20, c_21, c_22, c_23,
                              c_30, c_31, c_32, c_33
);

wire signed [7:0] a_row [0:3];
wire en_a [0:3];
wire signed [7:0] b_col [0:3];
wire en_b [0:3];

input_skew #(.N(4), .A_WIDTH(8)) u_skew (
    .clk   (clk),
    .rst_n (rst_n),
    .valid (valid),
    .a_vec (a_vec),
    .b_vec (b_vec),
    .a_row (a_row),
    .en_a  (en_a),
    .b_col (b_col),
    .en_b  (en_b)
);

systolic_4x4 u_sys (
    .clk   (clk),
    .rst_n (rst_n),
    .acc_clr (acc_clr),
    .a_row (a_row),
    .b_col (b_col),
    .en_a  (en_a),
    .en_b  (en_b),
    .c_00  (c_00), .c_01 (c_01), .c_02 (c_02), .c_03 (c_03),
    .c_10  (c_10), .c_11 (c_11), .c_12 (c_12), .c_13 (c_13),
    .c_20  (c_20), .c_21 (c_21), .c_22 (c_22), .c_23 (c_23),
    .c_30  (c_30), .c_31 (c_31), .c_32 (c_32), .c_33 (c_33)
);

endmodule
