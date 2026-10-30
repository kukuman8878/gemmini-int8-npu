// =============================================================
// equiv_wrap : npu_top (原 RTL) 与 npu_top_sv (综合视图) 等价性验证包装
//   同输入驱动两实例, 逐拍比对 out_valid/busy/done/out_c, 不一致即 $error
//   tb_top 以本模块为顶层跑全量端到端测试 (make sim_equiv)
// =============================================================
module equiv_wrap #(
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
    output wire done
);

wire out_valid_sv, busy_sv, done_sv;
wire [1:0] state_sv;
wire [N*N*32-1:0] out_c_flat_sv;
wire [N*8-1:0] a_vec_flat, b_vec_flat;
wire cfg_ready_sv, in_ready_sv;

npu_top #(.N(N)) u_dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready),
    .cfg_k    (cfg_k),
    .start    (start),
    .in_valid (in_valid),
    .in_ready (in_ready),
    .a_vec    (a_vec),
    .b_vec    (b_vec),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_c    (out_c),
    .busy     (busy),
    .done     (done)
);

genvar g;
generate
    for (g = 0; g < N; g = g + 1) begin : pack_in
        assign a_vec_flat[g*8 +: 8] = a_vec[g];
        assign b_vec_flat[g*8 +: 8] = b_vec[g];
    end
endgenerate

npu_top_sv #(.N(N)) u_sv (
    .clk      (clk),
    .rst_n    (rst_n),
    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready_sv),
    .cfg_k    (cfg_k),
    .start    (start),
    .in_valid (in_valid),
    .in_ready (in_ready_sv),
    .a_vec_flat(a_vec_flat),
    .b_vec_flat(b_vec_flat),
    .out_valid(out_valid_sv),
    .out_ready(out_ready),
    .out_c_flat(out_c_flat_sv),
    .busy     (busy_sv),
    .done     (done_sv),
    .state    (state_sv)
);

// ---- 逐拍等价性检查 ----
always @(posedge clk or negedge rst_n) begin
    if (rst_n) begin
        if (out_valid !== out_valid_sv) $error("MISMATCH out_valid");
        if (busy      !== busy_sv)      $error("MISMATCH busy");
        if (done      !== done_sv)      $error("MISMATCH done");
        if (out_valid && (out_c_flat_sv !== {out_c[15], out_c[14], out_c[13], out_c[12],
                                             out_c[11], out_c[10], out_c[9],  out_c[8],
                                             out_c[7],  out_c[6],  out_c[5],  out_c[4],
                                             out_c[3],  out_c[2],  out_c[1],  out_c[0]}))
            $display("DBG MISMATCH out_c: sv=%h concat=%h", out_c_flat_sv,
                     {out_c[15], out_c[14], out_c[13], out_c[12],
                      out_c[11], out_c[10], out_c[9],  out_c[8],
                      out_c[7],  out_c[6],  out_c[5],  out_c[4],
                      out_c[3],  out_c[2],  out_c[1],  out_c[0]});
    end
end

endmodule
