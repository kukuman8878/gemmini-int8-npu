// =============================================================
// systolic_array_cs_sv : 综合视图 (打包端口) —— 行为与 rtl/systolic_array_cs.sv 等价
//   yosys 不支持非压缩数组端口; 端口打包为扁平总线, 内部保持原结构
//   等价性由 tb/equiv_wrap.sv + tb_top 逐拍比对验证
// =============================================================
module systolic_array_cs_sv #(
    parameter N = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,
    input  wire [N*8-1:0]  a_row_flat,   // A 行斜排输入 (行 i 占 [i*8 +: 8])
    input  wire [N*8-1:0]  b_col_flat,   // B 列斜排输入
    input  wire [N-1:0]    en_a_flat,
    input  wire [N-1:0]    en_b_flat,
    output wire [N*N*32-1:0] c_flat_out    // 行优先拍平 C
);

// ---- 内部非压缩结构 (与原始模块一致) ----
wire signed [7:0] a_row [0:N-1];
wire signed [7:0] b_col [0:N-1];
wire en_a [0:N-1];
wire en_b [0:N-1];
wire signed [7:0] a_h [0:N-1][0:N];
wire en_a_h [0:N-1][0:N];
wire signed [7:0] b_v [0:N][0:N-1];
wire en_b_v [0:N][0:N-1];
wire signed [31:0] c [0:N-1][0:N-1];

genvar i, j;
generate
    for (i = 0; i < N; i = i + 1) begin : unpack
        assign a_row[i] = a_row_flat[i*8 +: 8];
        assign b_col[i] = b_col_flat[i*8 +: 8];
        assign en_a[i]  = en_a_flat[i];
        assign en_b[i]  = en_b_flat[i];
    end

    for (i = 0; i < N; i = i + 1) begin : left_in
        assign a_h[i][0]    = a_row[i];
        assign en_a_h[i][0] = en_a[i];
    end
    for (j = 0; j < N; j = j + 1) begin : top_in
        assign b_v[0][j]    = b_col[j];
        assign en_b_v[0][j] = en_b[j];
    end

    for (i = 0; i < N; i = i + 1) begin : row
        for (j = 0; j < N; j = j + 1) begin : col
            pe_cs u_pe (
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

    for (i = 0; i < N; i = i + 1) begin : pack_i
        for (j = 0; j < N; j = j + 1) begin : pack_j
            assign c_flat_out[(i*N+j)*32 +: 32] = c[i][j];
        end
    end
endgenerate

endmodule
