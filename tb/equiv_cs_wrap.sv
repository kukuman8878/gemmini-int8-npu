// =============================================================
// equiv_cs_wrap : npu_top (baseline) 与 npu_top_cs (carry-select) 等价性验证
//   接口/时序完全一致 (acc 均为寄存器输出), out_valid 时逐元素比对 out_c
// =============================================================
module equiv_cs_wrap #(
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

    wire out_valid_cs;
    /* verilator lint_off UNUSEDSIGNAL */  // busy/done 同 controller 恒等, 不比对
    wire busy_cs, done_cs;
    /* verilator lint_on UNUSEDSIGNAL */
    wire signed [31:0] out_c_cs [0:N*N-1];

    /* verilator lint_off PINCONNECTEMPTY */
    npu_top #(.N(N)) u_base (
        .clk      (clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_k(cfg_k),
        .start(start), .in_valid(in_valid), .in_ready(in_ready),
        .a_vec(a_vec), .b_vec(b_vec),
        .out_valid(out_valid), .out_ready(out_ready), .out_c(out_c),
        .busy(busy), .done(done), .state()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    npu_top_cs #(.N(N)) u_cs (
        .clk      (clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(), .cfg_k(cfg_k),
        .start(start), .in_valid(in_valid), .in_ready(),
        .a_vec(a_vec), .b_vec(b_vec),
        .out_valid(out_valid_cs), .out_ready(out_ready), .out_c(out_c_cs),
        .busy(busy_cs), .done(done_cs), .state()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    integer mismatch_cnt;
    initial mismatch_cnt = 0;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (rst_n) begin
            if (out_valid !== out_valid_cs) begin mismatch_cnt <= mismatch_cnt + 1; $error("MISMATCH out_valid"); end
            if (out_valid) begin
                for (k = 0; k < N * N; k = k + 1) begin
                    if (out_c[k] !== out_c_cs[k]) begin
                        mismatch_cnt <= mismatch_cnt + 1;
                        $display("DBG MISMATCH out_c[%0d]: base=%h cs=%h", k, out_c[k], out_c_cs[k]);
                        $error("MISMATCH out_c");
                    end
                end
            end
        end
    end

    final begin
        if (mismatch_cnt != 0)
            $fatal(1, "equiv_cs_wrap: %0d mismatches detected", mismatch_cnt);
    end

endmodule
