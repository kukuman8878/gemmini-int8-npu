// =============================================================
// equiv_opt_wrap : npu_top (baseline) 与 npu_top_opt (CSA optimized) 等价性验证
//   同输入驱动两实例; 分别握手捕获各自 out_c, 逐元素比对结果值
//   optimized 输出流水比 baseline 多 1 拍 (out_ready 恒 1 独立握手), 故捕获后比对
//   tb_top 以本模块为顶层 (输出采用 baseline 视角) 跑全量端到端测试
// =============================================================
module equiv_opt_wrap #(
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

    wire out_valid_opt;
    /* verilator lint_off UNUSEDSIGNAL */  // busy/done 时序因输出流水相差 1 拍, 不比对
    wire busy_opt, done_opt;
    /* verilator lint_on UNUSEDSIGNAL */
    wire signed [31:0] out_c_opt [0:N*N-1];

    /* verilator lint_off PINCONNECTEMPTY */
    npu_top #(.N(N)) u_base (
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
        .state    ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    /* verilator lint_off PINCONNECTEMPTY */
    npu_top_opt #(.N(N)) u_opt (
        .clk      (clk),
        .rst_n    (rst_n),
        .cfg_valid(cfg_valid),
        .cfg_ready(),
        .cfg_k    (cfg_k),
        .start    (start),
        .in_valid (in_valid),
        .in_ready (),
        .a_vec    (a_vec),
        .b_vec    (b_vec),
        .out_valid(out_valid_opt),
        .out_ready(1'b1),
        .out_c    (out_c_opt),
        .busy     (busy_opt),
        .done     (done_opt),
        .state    ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // 捕获 + 比对 (icarus $error 非致命 -> 计数器 + final $fatal)
    integer mismatch_cnt;
    initial mismatch_cnt = 0;

    reg [N*N*32-1:0] base_cap, opt_cap;
    reg base_cap_v, opt_cap_v;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_cap_v <= 1'b0;
            opt_cap_v  <= 1'b0;
            base_cap   <= {N*N*32{1'b0}};
            opt_cap    <= {N*N*32{1'b0}};
        end else begin
            // baseline 握手捕获 (out_valid && out_ready)
            if (out_valid && out_ready && !base_cap_v) begin
                for (k = 0; k < N * N; k = k + 1)
                    base_cap[k*32 +: 32] <= out_c[k];
                base_cap_v <= 1'b1;
            end
            // optimized 握手捕获 (out_ready 恒 1)
            if (out_valid_opt && !opt_cap_v) begin
                for (k = 0; k < N * N; k = k + 1)
                    opt_cap[k*32 +: 32] <= out_c_opt[k];
                opt_cap_v <= 1'b1;
            end
            // 都捕获后比对, 然后重置迎接下一任务
            if (base_cap_v && opt_cap_v) begin
                if (base_cap !== opt_cap) begin
                    mismatch_cnt <= mismatch_cnt + 1;
                    $display("DBG MISMATCH: base=%h opt=%h", base_cap, opt_cap);
                    $error("MISMATCH out_c result");
                end
                base_cap_v <= 1'b0;
                opt_cap_v  <= 1'b0;
            end
        end
    end

    final begin
        if (mismatch_cnt != 0)
            $fatal(1, "equiv_opt_wrap: %0d result mismatches detected", mismatch_cnt);
    end

endmodule
