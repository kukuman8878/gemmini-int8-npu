// =============================================================
// controller : 任务生命周期 FSM
//   IDLE -> LOAD(K 拍接受切片) -> DRAIN(2N-1 拍排空) -> OUTPUT(握手) -> IDLE
//   语义决策 (docs/03 §3, W5 锁定):
//   - busy 时拒绝 cfg (cfg_ready=0) 与 start (忽略)
//   - 输出等待期间不允许下一任务 (FSM 串行)
//   - done = 输出完成握手沿后一拍的单拍脉冲 (寄存器输出)
//   - out_valid 在 DRAIN 结束沿后置位 (结果已稳定)
//   - cfg 与 start 不能同拍生效; K 合法域 1..256, 非法 cfg 被拒绝
// =============================================================
module controller #(
    parameter N = 4,            // 阵列维度 (排空周期 2N-1); 约束: N >= 2
    parameter K_WIDTH = 9       // K 编码位宽 (1..256); 约束: K_WIDTH >= 9
) (
    input  wire clk,
    input  wire rst_n,
    // 配置握手 (仅 IDLE)
    input  wire cfg_valid,
    output wire cfg_ready,
    input  wire [K_WIDTH-1:0] cfg_k,
    // 启动 (仅 IDLE 且已配置)
    input  wire start,
    // 数据输入握手 (LOAD 阶段)
    input  wire in_valid,
    output wire in_ready,
    output wire in_accept,      // = in_valid && in_ready, 驱动 input_skew.valid
    // 结果输出握手 (OUTPUT 阶段)
    output wire out_valid,
    input  wire out_ready,
    // 状态
    output wire busy,
    output reg  done,               // 输出完成握手的单拍脉冲 (寄存器输出)
    output reg  [1:0] state
);

localparam S_IDLE  = 2'd0;
localparam S_LOAD  = 2'd1;
localparam S_DRAIN = 2'd2;
localparam S_OUT   = 2'd3;

// 排空 2N-1 拍, 计数 0..2N-2
localparam DR_CNT_W = $clog2(2 * N - 1);

reg [K_WIDTH-1:0] k_reg;          // 已配置 K
reg cfg_done;                     // 配置有效标志 (任务完成后清零)
reg [K_WIDTH-1:0] k_cnt;          // 已接受切片数
reg [DR_CNT_W-1:0] drain_cnt;     // 排空计数

wire cfg_ok   = (cfg_k >= 1) && (cfg_k <= 256);
wire accept_w = (state == S_LOAD) && in_valid;

assign in_ready  = (state == S_LOAD);
assign in_accept = accept_w;
assign cfg_ready = (state == S_IDLE);
assign out_valid = (state == S_OUT);
assign busy      = (state != S_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= S_IDLE;
        done      <= 1'b0;
        k_reg     <= {K_WIDTH{1'b0}};
        cfg_done  <= 1'b0;
        k_cnt     <= {K_WIDTH{1'b0}};
        drain_cnt <= {DR_CNT_W{1'b0}};
    end else begin
        done <= (state == S_OUT) && out_ready;   // 握手沿后的单拍脉冲
        case (state)
            S_IDLE: begin
                if (cfg_valid && cfg_ready && cfg_ok) begin
                    k_reg    <= cfg_k;
                    cfg_done <= 1'b1;
                end
                // 决策6: 同拍 cfg+start 时 start 无效 (本拍 cfg 仍被接收)
                if (start && cfg_done && !cfg_valid) begin
                    state     <= S_LOAD;
                    k_cnt     <= {K_WIDTH{1'b0}};
                    drain_cnt <= {DR_CNT_W{1'b0}};
                end
            end
            S_LOAD: begin
                if (accept_w) begin
                    k_cnt <= k_cnt + 1'b1;
                    if (k_cnt == k_reg - 1)      // 第 K 拍接受完成
                        state <= S_DRAIN;
                end
            end
            S_DRAIN: begin
                drain_cnt <= drain_cnt + 1'b1;
                if (drain_cnt == 2 * N - 2)      // 2N-1 拍排空完成
                    state <= S_OUT;
            end
            S_OUT: begin
                if (out_ready) begin
                    state    <= S_IDLE;
                    cfg_done <= 1'b0;            // 任务完成, 需重新配置
                end
            end
            default: state <= S_IDLE;
        endcase
    end
end

endmodule
