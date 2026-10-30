// =============================================================
// systolic_array_opt : N x N 脉动阵列 (W10 optimized) —— 使用 pe_opt (CSA)
//   结构/接口与 systolic_array.sv 完全一致, 仅 PE 换成 carry-save 累加器
//   输出 c_flat[i*N+j] = C[i][j] (pe_opt 组合合并 sum+carry)
// =============================================================
module systolic_array_opt #(
    parameter N = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,
    input  wire signed [7:0] a_row [0:N-1],
    input  wire signed [7:0] b_col [0:N-1],
    input  wire        en_a  [0:N-1],
    input  wire        en_b  [0:N-1],
    output wire signed [31:0] c_flat [0:N*N-1]
);

    wire signed [7:0] a_h [0:N-1][0:N];
    wire en_a_h [0:N-1][0:N];
    wire signed [7:0] b_v [0:N][0:N-1];
    wire en_b_v [0:N][0:N-1];
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
                pe_opt u_pe (
                    .clk   (clk),
                    .rst_n (rst_n),
                    .acc_clr (acc_clr),
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
                assign c_flat[i*N+j] = c[i][j];
            end
        end
    endgenerate

endmodule
