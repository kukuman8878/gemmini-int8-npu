// =============================================================
// pe_opt2 : 脉动阵列处理单元 (W15 optimized) —— CSA 累加器 + 分量输出
//   与 pe_opt.sv 唯一差异: 不做组合 32 位合并, 直接输出 sum 与 carry 两个分量
//   合并加法器由顶层 (npu_top_opt2) 做 carry-select 2 级流水, 缩短关键路径
//   接口/累加语义与 pe_opt.sv 一致 (2 补码回绕, acc_clr 优先, 转发不冻结)
// =============================================================
module pe_opt2 #(
    parameter A_WIDTH   = 8,
    parameter ACC_WIDTH = 32
) (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,
    input  wire signed [A_WIDTH-1:0]  a_in,
    input  wire signed [A_WIDTH-1:0]  b_in,
    input  wire        en_a,
    input  wire        en_b,
    output reg  signed [A_WIDTH-1:0]  a_out,
    output reg  signed [A_WIDTH-1:0]  b_out,
    output reg         en_a_out,
    output reg         en_b_out,
    output wire signed [ACC_WIDTH-1:0] sum,    // carry-save 部分和
    output wire signed [ACC_WIDTH-1:0] carry   // carry<<1 (权重 2^1)
);

    reg signed [ACC_WIDTH-1:0] acc_sum;
    /* verilator lint_off UNUSEDSIGNAL */
    reg signed [ACC_WIDTH-1:0] acc_carry;
    /* verilator lint_on UNUSEDSIGNAL */

    wire signed [2*A_WIDTH-1:0] prod    = a_in * b_in;
    wire signed [ACC_WIDTH-1:0] p       = {{ACC_WIDTH-2*A_WIDTH{prod[2*A_WIDTH-1]}}, prod};
    wire        [ACC_WIDTH-1:0] c_sh    = {acc_carry[ACC_WIDTH-2:0], 1'b0};
    wire        [ACC_WIDTH-1:0] t1      = p ^ acc_sum;
    wire        [ACC_WIDTH-1:0] sum_nxt = t1 ^ c_sh;
    wire        [ACC_WIDTH-1:0] carry_nxt = (p & acc_sum) | (t1 & c_sh);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out     <= {A_WIDTH{1'b0}};
            b_out     <= {A_WIDTH{1'b0}};
            en_a_out  <= 1'b0;
            en_b_out  <= 1'b0;
            acc_sum   <= {ACC_WIDTH{1'b0}};
            acc_carry <= {ACC_WIDTH{1'b0}};
        end else begin
            a_out    <= a_in;
            b_out    <= b_in;
            en_a_out <= en_a;
            en_b_out <= en_b;
            if (acc_clr) begin
                acc_sum   <= {ACC_WIDTH{1'b0}};
                acc_carry <= {ACC_WIDTH{1'b0}};
            end else if (en_a && en_b) begin
                acc_sum   <= sum_nxt;
                acc_carry <= carry_nxt;
            end
        end
    end

    assign sum   = acc_sum;
    assign carry = c_sh;

endmodule
