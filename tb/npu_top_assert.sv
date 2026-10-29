// =============================================================
// npu_top_assert : npu_top 的 SVA 断言包装 (仅验证用)
//   断言在 Verilator --assert 后端执行 (make sim_top_sva)
//   A1 背压稳定 / A3 busy-state 一致 / A4 复位合法态 / A6 完成进度
// =============================================================
module npu_top_assert #(
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
    .state    (state)
);

// packed 影子信号 (SVA 需要标量/向量, 非压缩数组无法直接 $stable)
wire [N*N*32-1:0] out_c_packed;
genvar g;
generate
    for (g = 0; g < N*N; g = g + 1) begin : pack
        assign out_c_packed[g*32 +: 32] = out_c[g];
    end
endgenerate

// A1: 背压期间 out_c 必须稳定 (契约: valid&&!ready 时数据保持)
assert property (@(posedge clk) disable iff (!rst_n)
    (out_valid && !out_ready) |=> $stable(out_c_packed));

// A3: busy 与控制状态一致
assert property (@(posedge clk) disable iff (!rst_n)
    (busy == (state != 2'd0)));

// A3b: 接口一致性 (out_valid/in_ready/cfg_ready 与 busy 的关系)
assert property (@(posedge clk) disable iff (!rst_n) (out_valid |-> busy));
assert property (@(posedge clk) disable iff (!rst_n) (in_ready |-> busy));
assert property (@(posedge clk) disable iff (!rst_n) (cfg_ready |-> !busy));

// A4: 复位释放后状态合法 (IDLE, 无输出)
assert property (@(posedge clk) disable iff (!rst_n)
    $rose(rst_n) |=> ((state == 2'd0) && !busy && !out_valid));

// A6: 完成进度: 任务必须在有界时间内结束 (1..64 拍)
assert property (@(posedge clk) disable iff (!rst_n)
    busy |-> ##[1:64] !busy);

endmodule
