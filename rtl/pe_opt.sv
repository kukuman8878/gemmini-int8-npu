// =============================================================
// pe_opt : 脉动阵列处理单元 (W10 optimized 变体) —— carry-save 累加器
//   与 pe.sv 相比唯一差异: 累加器改为 carry-save (sum+carry 双寄存器)
//   累加环关键路径 = 乘法部分积 + 3:2 压缩 (XOR/majority), 不再是 32 位进位链
//   输出 acc = acc_sum + (acc_carry << 1) 为组合合并 (位于输出路径, 非累加环)
//   接口/时序/累加语义与 pe.sv 一致 (2 补码回绕, acc_clr 优先, 转发不冻结)
// =============================================================
module pe_opt #(
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
    output wire signed [ACC_WIDTH-1:0] acc
);

    reg signed [ACC_WIDTH-1:0] acc_sum;    // carry-save: 部分和
    /* verilator lint_off UNUSEDSIGNAL */  // carry[31] 在左移合并时溢出, 永不读
    reg signed [ACC_WIDTH-1:0] acc_carry;  // carry-save: 进位 (权重 2^1)
    /* verilator lint_on UNUSEDSIGNAL */

    // 乘积累加: 每拍 3:2 压缩 p + sum + (carry<<1) -> 新 sum/carry
    // 注: 8x8 signed 乘法结果先取 16bit 再符号扩展到 ACC_WIDTH
    //     (不能写 $signed(a_in*b_in), Icarus 会将其截断为 8bit)
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

    // 输出合并 (只在输出路径, 组合 32 位加法)
    assign acc = acc_sum + $signed(c_sh);

endmodule
