// =============================================================
// input_skew : OS 脉动阵列输入错位 (skew)
//   每拍输入 A 的列切片 a_vec[i] = A[i][k] 与 B 的行切片 b_vec[j] = B[k][j]
//   valid=1 表示本拍切片有效 (k < K, K 为归约长度)
//   输出为左/上边界的错位流: A 第 i 行延迟 1+i 拍, B 第 j 列延迟 1+j 拍
//   (A/B 同幅偏移, 相对对齐不变; 相比驱动端直灌多 1 拍流水延迟)
//   注: 首版无背压 (valid 仅门控数据, 停顿语义见 docs/03 §1 TODO-决策)
// =============================================================
module input_skew #(
    parameter N = 4,        // 阵列维度
    parameter A_WIDTH = 8   // 输入位宽
) (
    input  wire clk,
    input  wire rst_n,
    input  wire valid,
    input  wire signed [A_WIDTH-1:0] a_vec [0:N-1],
    input  wire signed [A_WIDTH-1:0] b_vec [0:N-1],
    output wire signed [A_WIDTH-1:0] a_row [0:N-1],
    output wire en_a  [0:N-1],
    output wire signed [A_WIDTH-1:0] b_col [0:N-1],
    output wire en_b  [0:N-1]
);

// ---- 移位链: [i][d] = 通道 i 的第 d 拍快照 ----
reg signed [A_WIDTH-1:0] a_d [0:N-1][0:N-1];
reg a_v [0:N-1][0:N-1];
reg signed [A_WIDTH-1:0] b_d [0:N-1][0:N-1];
reg b_v [0:N-1][0:N-1];

integer i, d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < N; i = i + 1) begin
            for (d = 0; d < N; d = d + 1) begin
                a_d[i][d] <= {A_WIDTH{1'b0}};
                b_d[i][d] <= {A_WIDTH{1'b0}};
                a_v[i][d] <= 1'b0;
                b_v[i][d] <= 1'b0;
            end
        end
    end else begin
        for (i = 0; i < N; i = i + 1) begin
            a_d[i][0] <= a_vec[i];
            a_v[i][0] <= valid;
            b_d[i][0] <= b_vec[i];
            b_v[i][0] <= valid;
            for (d = 1; d < N; d = d + 1) begin
                a_d[i][d] <= a_d[i][d-1];
                a_v[i][d] <= a_v[i][d-1];
                b_d[i][d] <= b_d[i][d-1];
                b_v[i][d] <= b_v[i][d-1];
            end
        end
    end
end

// ---- 抽头: 通道 i 取第 i 拍快照 → 相对错位 i 拍 ----
generate
    genvar g;
    for (g = 0; g < N; g = g + 1) begin : tap
        assign a_row[g] = a_d[g][g];
        assign en_a[g]  = a_v[g][g];
        assign b_col[g] = b_d[g][g];
        assign en_b[g]  = b_v[g][g];
    end
endgenerate

endmodule
