// =============================================================
// npu_top_opt : 顶层集成 (W10 optimized) —— CSA 阵列 + 输出流水寄存器
//   与 npu_top.sv 接口一致; 差异:
//   - 阵列用 pe_opt (carry-save 累加器), 组合合并 32 位加法移到输出路径
//   - out_c 加一级寄存器, out_valid/done 同步打拍 1 级 (输出握手重定时)
//     累加环 (每拍) 不再经过 32 位进位链; OUTPUT 阶段比 baseline 多 1 拍
// =============================================================
module npu_top_opt #(
    parameter N = 4
) (
    input  wire clk,
    input  wire rst_n,
    input  wire cfg_valid,
    output wire cfg_ready,
    input  wire [8:0] cfg_k,
    input  wire start,
    input  wire in_valid,
    output wire in_ready,
    input  wire signed [7:0] a_vec [0:N-1],
    input  wire signed [7:0] b_vec [0:N-1],
    output wire out_valid,
    input  wire out_ready,
    output wire signed [31:0] out_c [0:N*N-1],
    output wire busy,
    output wire done,
    output wire [1:0] state
);

    localparam S_IDLE = 2'd0;

    wire in_accept;
    wire signed [7:0] a_row [0:N-1];
    wire en_a [0:N-1];
    wire signed [7:0] b_col [0:N-1];
    wire en_b [0:N-1];
    wire signed [31:0] c_comb [0:N*N-1];
    reg  signed [31:0] out_c_reg [0:N*N-1];

    wire out_valid_ctrl, done_ctrl;
    reg  out_valid_reg, done_reg;

    controller #(.N(N)) u_ctrl (
        .clk      (clk),
        .rst_n    (rst_n),
        .cfg_valid(cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_k    (cfg_k),
        .start    (start),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .in_accept(in_accept),
        .out_valid(out_valid_ctrl),
        .out_ready(out_ready),
        .busy     (busy),
        .done     (done_ctrl),
        .state    (state)
    );

    input_skew #(.N(N)) u_skew (
        .clk   (clk),
        .rst_n (rst_n),
        .valid (in_accept),
        .a_vec (a_vec),
        .b_vec (b_vec),
        .a_row (a_row),
        .en_a  (en_a),
        .b_col (b_col),
        .en_b  (en_b)
    );

    systolic_array_opt #(.N(N)) u_sys (
        .clk     (clk),
        .rst_n   (rst_n),
        .acc_clr (state == S_IDLE),
        .a_row   (a_row),
        .b_col   (b_col),
        .en_a    (en_a),
        .en_b    (en_b),
        .c_flat  (c_comb)
    );

    // 输出流水 (1 级): out_c / out_valid / done 同步打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < N * N; k = k + 1)
                out_c_reg[k] <= 32'sd0;
            out_valid_reg <= 1'b0;
            done_reg      <= 1'b0;
        end else begin
            for (int k = 0; k < N * N; k = k + 1)
                out_c_reg[k] <= c_comb[k];
            out_valid_reg <= out_valid_ctrl;
            done_reg      <= done_ctrl;
        end
    end

    assign out_valid = out_valid_reg;
    assign out_c     = out_c_reg;
    assign done      = done_reg;

endmodule
