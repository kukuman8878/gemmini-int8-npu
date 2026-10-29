// =============================================================
// systolic_array : N x N 脉动阵列 (参数化)
//   输入: A 矩阵按行斜排从左进, B 矩阵按列斜排从上进
//   输出: c_flat[i*N+j] = C[i][j] (行优先拍平, K=N 满速时 3N-2 拍后全部就绪,
//         K<N 部分归约时为 2N+K-2 拍)
//   例: N=4 为 4x4 阵列, N=8 为 8x8 阵列
// =============================================================
module systolic_array #(
    parameter N = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire signed [7:0] a_row [0:N-1],
    input  wire signed [7:0] b_col [0:N-1],
    input  wire        en_a  [0:N-1],
    input  wire        en_b  [0:N-1],
    output wire signed [31:0] c_flat [0:N*N-1]   // 1D 拍平 (行优先)
);

// ---- 水平通道: 每行 N+1 个节点 ----
wire signed [7:0] a_h [0:N-1][0:N];
wire en_a_h [0:N-1][0:N];

// ---- 垂直通道: 每列 N+1 个节点 ----
wire signed [7:0] b_v [0:N][0:N-1];
wire en_b_v [0:N][0:N-1];

// ---- 内部 2D 结果 ----
wire signed [31:0] c [0:N-1][0:N-1];

genvar i;
genvar j;
generate
    for (i = 0; i < N; i = i + 1) begin: left_in
        assign a_h[i][0]    = a_row[i];
        assign en_a_h[i][0] = en_a[i];
    end
    for (j = 0; j < N; j = j + 1) begin: top_in
        assign b_v[0][j]    = b_col[j];
        assign en_b_v[0][j] = en_b[j];
    end

    for (i = 0; i < N; i = i + 1) begin: row
        for (j = 0; j < N; j = j + 1) begin: col
            pe u_pe (
                .clk   (clk),
                .rst_n (rst_n),
                .a_in  (a_h[i][j]),
                .b_in  (b_v[i][j]),
                .en_a  (en_a_h[i][j]),
                .en_b  (en_b_v[i][j]),
                .a_out (a_h[i][j+1]),
                .b_out (b_v[i+1][j]),
                .en_a_out (en_a_h[i][j+1]),
                .en_b_out (en_b_v[i+1][j]),
                .acc   (c[i][j])
            );
        end
    end

    for (i = 0; i < N; i = i + 1) begin: flat_i
        for (j = 0; j < N; j = j + 1) begin: flat_j
            assign c_flat[i*N+j] = c[i][j];   // 行优先拍平
        end
    end
endgenerate

endmodule
