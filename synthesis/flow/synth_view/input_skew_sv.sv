// =============================================================
// input_skew_sv : 综合视图 (打包端口) —— 行为与 rtl/input_skew.sv 等价
// =============================================================
module input_skew_sv #(
    parameter N = 4,
    parameter A_WIDTH = 8
) (
    input  wire clk,
    input  wire rst_n,
    input  wire valid,
    input  wire [N*A_WIDTH-1:0] a_vec_flat,
    input  wire [N*A_WIDTH-1:0] b_vec_flat,
    output wire [N*A_WIDTH-1:0] a_row_flat,
    output wire [N-1:0]         en_a_flat,
    output wire [N*A_WIDTH-1:0] b_col_flat,
    output wire [N-1:0]         en_b_flat
);

// ---- 内部非压缩结构 (与原始模块一致) ----
wire signed [A_WIDTH-1:0] a_vec [0:N-1];
wire signed [A_WIDTH-1:0] b_vec [0:N-1];
reg  signed [A_WIDTH-1:0] a_d [0:N-1][0:N-1];
reg  a_v [0:N-1][0:N-1];
reg  signed [A_WIDTH-1:0] b_d [0:N-1][0:N-1];
reg  b_v [0:N-1][0:N-1];

genvar g;
generate
    for (g = 0; g < N; g = g + 1) begin : unpack
        assign a_vec[g] = a_vec_flat[g*A_WIDTH +: A_WIDTH];
        assign b_vec[g] = b_vec_flat[g*A_WIDTH +: A_WIDTH];
    end
endgenerate

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

generate
    for (g = 0; g < N; g = g + 1) begin : tap
        assign a_row_flat[g*A_WIDTH +: A_WIDTH] = a_d[g][g];
        assign en_a_flat[g]                    = a_v[g][g];
        assign b_col_flat[g*A_WIDTH +: A_WIDTH] = b_d[g][g];
        assign en_b_flat[g]                    = b_v[g][g];
    end
endgenerate

endmodule
