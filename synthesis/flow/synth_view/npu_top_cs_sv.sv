// =============================================================
// !! 维护提醒: 修改 rtl/ 对应模块后必须同步更新本副本 (make sim_equiv 验证等价性) !!
// npu_top_cs_sv : 综合视图 (打包端口) —— 行为与 rtl/npu_top_cs.sv 等价
//   综合入口 (yosys 不支持非压缩数组端口)
// =============================================================
module npu_top_cs_sv #(
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

wire in_accept;
wire [N*8-1:0] a_row_flat;
wire [N-1:0] en_a_flat;
wire [N*8-1:0] b_col_flat;
wire [N-1:0] en_b_flat;

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
    .out_valid(out_valid),
    .out_ready(out_ready),
    .busy     (busy),
    .done     (done),
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

systolic_array_cs_sv #(.N(N)) u_sys (
    .clk       (clk),
    .rst_n     (rst_n),
    .acc_clr   (state == 2'd0),
    .a_row_flat(a_row_flat),
    .b_col_flat(b_col_flat),
    .en_a_flat (en_a_flat),
    .en_b_flat (en_b_flat),
    .c_flat_out(out_c_flat)
);

endmodule
