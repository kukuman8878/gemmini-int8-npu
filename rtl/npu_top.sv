// =============================================================
// npu_top : 顶层集成 (controller + input_skew + 脉动阵列)
//   任务流: cfg(K) -> start -> LOAD(K 拍切片) -> 自动排空 -> OUTPUT 握手
//   acc_clr 在 IDLE 态持续置位: 任务边界清零 (清零覆盖整个残留窗口)
//   端口契约见 docs/03 §3 (W5 已锁定决策)
// =============================================================
module npu_top #(
    parameter N = 4             // 阵列维度 (4x4)
) (
    input  wire clk,
    input  wire rst_n,
    // 配置握手 (仅 IDLE)
    input  wire cfg_valid,
    output wire cfg_ready,
    input  wire [8:0] cfg_k,    // 归约长度 K (1..256)
    // 启动
    input  wire start,
    // 数据输入握手 (LOAD 阶段): 每拍一个归约切片
    input  wire in_valid,
    output wire in_ready,
    input  wire signed [7:0] a_vec [0:N-1],  // A 列切片 a_vec[i]=A[i][k]
    input  wire signed [7:0] b_vec [0:N-1],  // B 行切片 b_vec[j]=B[k][j]
    // 结果输出握手 (OUTPUT 阶段)
    output wire out_valid,
    input  wire out_ready,
    output wire signed [31:0] out_c [0:N*N-1],  // 行优先拍平 C[i][j]
    // 状态
    output wire busy,
    output wire done,
    output wire [1:0] state   // 调试口 (断言/观测用, 见 tb/npu_top_assert.sv)
);

wire in_accept;
wire signed [7:0] a_row [0:N-1];
wire en_a [0:N-1];
wire signed [7:0] b_col [0:N-1];
wire en_b [0:N-1];

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

systolic_array #(.N(N)) u_sys (
    .clk     (clk),
    .rst_n   (rst_n),
    .acc_clr (state == 2'd0),   // IDLE 态持续清零 (任务边界)
    .a_row   (a_row),
    .b_col   (b_col),
    .en_a    (en_a),
    .en_b    (en_b),
    .c_flat  (out_c)
);

endmodule
