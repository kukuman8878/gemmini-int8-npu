// =============================================================
// !! 维护提醒: 修改 rtl/ 对应模块后必须同步更新本副本 (make sim_equiv 验证等价性) !!
// npu_top_opt2_sv : 综合视图 (打包端口) —— 行为与 rtl/npu_top_opt2.sv 等价
//   CSA + carry-select 2 级输出流水
// =============================================================
module npu_top_opt2_sv #(
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
    wire [N*N*64-1:0] c_flat_64;
    wire out_valid_ctrl, done_ctrl;

    controller #(.N(N)) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_k(cfg_k),
        .start(start), .in_valid(in_valid), .in_ready(in_ready),
        .in_accept(in_accept), .out_valid(out_valid_ctrl), .out_ready(out_ready),
        .busy(busy), .done(done_ctrl), .state(state)
    );

    input_skew_sv #(.N(N)) u_skew (
        .clk(clk), .rst_n(rst_n), .valid(in_accept),
        .a_vec_flat(a_vec_flat), .b_vec_flat(b_vec_flat),
        .a_row_flat(a_row_flat), .en_a_flat(en_a_flat),
        .b_col_flat(b_col_flat), .en_b_flat(en_b_flat)
    );

    systolic_array_opt2_sv #(.N(N)) u_sys (
        .clk(clk), .rst_n(rst_n), .acc_clr(state == S_IDLE),
        .a_row_flat(a_row_flat), .b_col_flat(b_col_flat),
        .en_a_flat(en_a_flat), .en_b_flat(en_b_flat),
        .c_flat_out(c_flat_64)
    );

    genvar k;
    wire [31:0] sum_w  [0:N*N-1];
    wire [31:0] carry_w[0:N*N-1];
    wire [16:0] lo_ext [0:N*N-1];
    wire [15:0] hi_sum [0:N*N-1];
    reg  [15:0] lo_reg [0:N*N-1];
    reg         co_reg [0:N*N-1];
    reg  [N*N*32-1:0] out_c_reg;

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
                out_c_reg[kk*32 +: 32] <= 32'd0;
            end
            out_valid_pipe <= 2'd0;
            done_pipe      <= 2'd0;
        end else begin
            for (kk = 0; kk < N*N; kk = kk + 1) begin
                lo_reg[kk] <= lo_ext[kk][15:0];
                co_reg[kk] <= lo_ext[kk][16];
            end
            for (kk = 0; kk < N*N; kk = kk + 1) begin
                out_c_reg[kk*32 +: 32] <= {hi_sum[kk], lo_reg[kk]};
            end
            out_valid_pipe <= {out_valid_pipe[0], out_valid_ctrl};
            done_pipe      <= {done_pipe[0], done_ctrl};
        end
    end

    assign out_valid   = out_valid_pipe[1];
    assign done        = done_pipe[1];
    assign out_c_flat  = out_c_reg;

endmodule
