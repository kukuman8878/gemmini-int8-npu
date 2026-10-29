// =============================================================
// systolic_4x4 : 4x4 脉动阵列 (16 个 PE)
//   输入: A 矩阵按行斜排从左进, B 矩阵按列斜排从上进
//   输出: 每个 PE 的 acc = C[i][j] (10 拍后全部就绪)
// =============================================================
module systolic_4x4 (
    input  wire clk,
    input  wire rst_n,
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

// ---- 内部连线: 水平通道 (每行 5 个节点, 4个PE输入 + 右边界) ----
wire signed [7:0] a_h [0:3][0:4];
wire en_a_h [0:3][0:4];

// ---- 内部连线: 垂直通道 (每列 5 个节点, 4个PE输入 + 下边界) ----
wire signed [7:0] b_v [0:4][0:3];
wire en_b_v [0:4][0:3];

// ---- 内部 2D 结果连线 (供 generate 循环引用) ----
wire signed [31:0] c [0:3][0:3];

// ---- 边界注入: 外部输入接到通道起点 ----
genvar i;
genvar j;
generate
    for (i = 0; i < 4; i = i + 1) begin: left_in
        assign a_h[i][0]   = a_row[i];
        assign en_a_h[i][0] = en_a[i];
    end
    for (j = 0; j < 4; j = j + 1) begin: top_in
        assign b_v[0][j]   = b_col[j];
        assign en_b_v[0][j] = en_b[j];
    end

    // ---- 16 个 PE ----
    for (i = 0; i < 4; i = i + 1) begin: row
        for (j = 0; j < 4; j = j + 1) begin: col
            pe u_pe (
                .clk   (clk),
                .rst_n (rst_n),
                .a_in  (a_h[i][j]),
                .b_in  (b_v[i][j]),
                .en_a  (en_a_h[i][j]),
                .en_b  (en_b_v[i][j]),
                .a_out (a_h[i][j+1]),     // 传给右边的 PE
                .b_out (b_v[i+1][j]),     // 传给下面的 PE
                .en_a_out (en_a_h[i][j+1]),
                .en_b_out (en_b_v[i+1][j]),
                .acc   (c[i][j])
            );
        end
    end
endgenerate

// ---- 内部 2D 结果 → 拍平的输出端口 ----
assign c_00 = c[0][0]; assign c_01 = c[0][1]; assign c_02 = c[0][2]; assign c_03 = c[0][3];
assign c_10 = c[1][0]; assign c_11 = c[1][1]; assign c_12 = c[1][2]; assign c_13 = c[1][3];
assign c_20 = c[2][0]; assign c_21 = c[2][1]; assign c_22 = c[2][2]; assign c_23 = c[2][3];
assign c_30 = c[3][0]; assign c_31 = c[3][1]; assign c_32 = c[3][2]; assign c_33 = c[3][3];

endmodule
