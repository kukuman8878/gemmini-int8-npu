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
wire [N*N*32-1:0] out_c_flat_sv;
wire [N*8-1:0] a_vec_flat, b_vec_flat;

/* verilator lint_off PINCONNECTEMPTY */
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
    .done     (done),
    .state    (/* unused: 仅调试口, 综合视图侧通过 u_sv.state 观测 */)
);
/* verilator lint_on PINCONNECTEMPTY */

genvar g;
generate
    for (g = 0; g < N; g = g + 1) begin : pack_in
        assign a_vec_flat[g*8 +: 8] = a_vec[g];
        assign b_vec_flat[g*8 +: 8] = b_vec[g];
    end
endgenerate

/* verilator lint_off PINMISSING */
npu_top_sv #(.N(N)) u_sv (
    .clk      (clk),
    .rst_n    (rst_n),
    .cfg_valid(cfg_valid),
    .cfg_k    (cfg_k),
    .start    (start),
    .in_valid (in_valid),
    .a_vec_flat(a_vec_flat),
    .b_vec_flat(b_vec_flat),
    .out_valid(out_valid_sv),
    .out_ready(out_ready),
    .out_c_flat(out_c_flat_sv),
    .busy     (busy_sv),
    .done     (done_sv)
);
/* verilator lint_on PINMISSING */

// ---- 逐拍等价性检查 ----
// 注: out_valid/busy/done 来自两实例共享的同一 controller 模块 (防御性冗余);
//     综合视图真正可分化的一切最终体现在 out_c 上 -> 不一致必须门禁
// icarus $error 非致命: 用计数器 + final 块 $fatal 保证退出码非零
integer mismatch_cnt;
initial mismatch_cnt = 0;

always @(posedge clk or negedge rst_n) begin
    if (rst_n) begin
        if (out_valid !== out_valid_sv) begin mismatch_cnt = mismatch_cnt + 1; $error("MISMATCH out_valid"); end
        if (busy      !== busy_sv)      begin mismatch_cnt = mismatch_cnt + 1; $error("MISMATCH busy"); end
        if (done      !== done_sv)      begin mismatch_cnt = mismatch_cnt + 1; $error("MISMATCH done"); end
        if (out_valid && (out_c_flat_sv !== {out_c[15], out_c[14], out_c[13], out_c[12],
                                             out_c[11], out_c[10], out_c[9],  out_c[8],
                                             out_c[7],  out_c[6],  out_c[5],  out_c[4],
                                             out_c[3],  out_c[2],  out_c[1],  out_c[0]})) begin
            mismatch_cnt = mismatch_cnt + 1;
            $display("DBG MISMATCH out_c: sv=%h concat=%h", out_c_flat_sv,
                     {out_c[15], out_c[14], out_c[13], out_c[12],
                      out_c[11], out_c[10], out_c[9],  out_c[8],
                      out_c[7],  out_c[6],  out_c[5],  out_c[4],
                      out_c[3],  out_c[2],  out_c[1],  out_c[0]});
            $error("MISMATCH out_c");
        end
    end
end

final begin
    if (mismatch_cnt != 0)
        $fatal(1, "equiv_wrap: %0d cycle-level mismatches detected", mismatch_cnt);
end

endmodule
