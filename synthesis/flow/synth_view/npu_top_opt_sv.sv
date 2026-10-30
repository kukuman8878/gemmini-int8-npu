// =============================================================
// !! 维护提醒: 修改 rtl/ 对应模块后必须同步更新本副本 (make sim_equiv 验证等价性) !!
// npu_top_opt_sv : 综合视图 (打包端口) —— 行为与 rtl/npu_top_opt.sv 等价
//   CSA 阵列 + 输出流水寄存器 (out_c/out_valid/done 同步打拍)
// =============================================================
module npu_top_opt_sv #(
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
    input  wire [N*8-1:0] a_vec_flat,
    input  wire [N*8-1:0] b_vec_flat,
    output wire out_valid,
    input  wire out_ready,
    output wire [N*N*32-1:0] out_c_flat,
    output wire busy,
    output wire done,
    output wire [1:0] state
);

    localparam S_IDLE = 2'd0;

    wire in_accept;
    wire [N*8-1:0] a_row_flat;
    wire [N-1:0] en_a_flat;
    wire [N*8-1:0] b_col_flat;
    wire [N-1:0] en_b_flat;
    wire [N*N*32-1:0] c_comb_flat;
    reg  [N*N*32-1:0] out_c_reg;

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

    input_skew_sv #(.N(N)) u_skew (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid      (in_accept),
        .a_vec_flat (a_vec_flat),
        .b_vec_flat (b_vec_flat),
        .a_row_flat (a_row_flat),
        .en_a_flat  (en_a_flat),
        .b_col_flat (b_col_flat),
        .en_b_flat  (en_b_flat)
    );

    systolic_array_opt_sv #(.N(N)) u_sys (
        .clk       (clk),
        .rst_n     (rst_n),
        .acc_clr   (state == S_IDLE),
        .a_row_flat(a_row_flat),
        .b_col_flat(b_col_flat),
        .en_a_flat (en_a_flat),
        .en_b_flat (en_b_flat),
        .c_flat_out(c_comb_flat)
    );

    // 输出流水 (1 级): out_c / out_valid / done 同步打拍
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_c_reg    <= {N*N*32{1'b0}};
            out_valid_reg <= 1'b0;
            done_reg      <= 1'b0;
        end else begin
            out_c_reg    <= c_comb_flat;
            out_valid_reg <= out_valid_ctrl;
            done_reg      <= done_ctrl;
        end
    end

    assign out_valid = out_valid_reg;
    assign out_c_flat = out_c_reg;
    assign done      = done_reg;

endmodule
