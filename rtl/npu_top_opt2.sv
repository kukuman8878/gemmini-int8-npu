// =============================================================
// npu_top_opt2 : 顶层集成 (W15 optimized) —— CSA + carry-select 2 级输出流水
//   与 npu_top_opt.sv (W10) 的差异: 输出合并 32 位加法拆成 carry-select 2 级流水
//   级1 = 低16位加法 (锁 lo+co), 级2 = 高16位加法 (锁 hi); 关键路径 = 16位加法
//   OUTPUT 阶段外部可见比 baseline 多 2 拍 (out_valid/done 同步打拍 2 级)
// =============================================================
module npu_top_opt2 #(
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
    wire [N*N*64-1:0] c_flat_64;

    wire out_valid_ctrl, done_ctrl;

    controller #(.N(N)) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_k(cfg_k),
        .start(start), .in_valid(in_valid), .in_ready(in_ready),
        .in_accept(in_accept),
        .out_valid(out_valid_ctrl), .out_ready(out_ready),
        .busy(busy), .done(done_ctrl), .state(state)
    );

    input_skew #(.N(N)) u_skew (
        .clk(clk), .rst_n(rst_n), .valid(in_accept),
        .a_vec(a_vec), .b_vec(b_vec),
        .a_row(a_row), .en_a(en_a), .b_col(b_col), .en_b(en_b)
    );

    systolic_array_opt2 #(.N(N)) u_sys (
        .clk(clk), .rst_n(rst_n), .acc_clr(state == S_IDLE),
        .a_row(a_row), .b_col(b_col), .en_a(en_a), .en_b(en_b),
        .c_flat_out(c_flat_64)
    );

    // ---- carry-select 2 级流水合并 (16 个元素) ----
    genvar k;
    wire [31:0] sum_w  [0:N*N-1];
    wire [31:0] carry_w[0:N*N-1];
    wire [16:0] lo_ext [0:N*N-1];   // 级1 组合: 低16位加法 (bit16=进位)
    wire [15:0] hi_sum [0:N*N-1];   // 级2 组合: 高16位加法
    reg  [15:0] lo_reg [0:N*N-1];
    reg         co_reg [0:N*N-1];
    reg  [31:0] out_c_reg [0:N*N-1];

    generate
        for (k = 0; k < N*N; k = k + 1) begin: merge
            assign sum_w[k]   = c_flat_64[k*64 +: 32];
            assign carry_w[k] = c_flat_64[k*64 + 32 +: 32];
            assign lo_ext[k]  = sum_w[k][15:0] + carry_w[k][15:0];
            assign hi_sum[k]  = sum_w[k][31:16] + carry_w[k][31:16] + {15'd0, co_reg[k]};
        end
    endgenerate

    reg [1:0] out_valid_pipe;
    reg [1:0] done_pipe;

    integer kk;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (kk = 0; kk < N*N; kk = kk + 1) begin
                lo_reg[kk] <= 16'd0;
                co_reg[kk] <= 1'b0;
                out_c_reg[kk] <= 32'd0;
            end
            out_valid_pipe <= 2'd0;
            done_pipe      <= 2'd0;
        end else begin
            // 级1: 低16位加法结果 + 进位
            for (kk = 0; kk < N*N; kk = kk + 1) begin
                lo_reg[kk] <= lo_ext[kk][15:0];
                co_reg[kk] <= lo_ext[kk][16];
            end
            // 级2: 高16位加法结果, 拼成最终 out_c
            for (kk = 0; kk < N*N; kk = kk + 1) begin
                out_c_reg[kk] <= {hi_sum[kk], lo_reg[kk]};
            end
            out_valid_pipe <= {out_valid_pipe[0], out_valid_ctrl};
            done_pipe      <= {done_pipe[0], done_ctrl};
        end
    end

    assign out_valid = out_valid_pipe[1];
    assign done      = done_pipe[1];

    generate
        for (k = 0; k < N*N; k = k + 1) begin: out_assign
            assign out_c[k] = out_c_reg[k];
        end
    endgenerate

endmodule
