// =============================================================
// pe_cs : 脉动阵列处理单元 (W10 optimized 变体 2) —— carry-select 累加器
//   与 pe.sv 相同接口/时序/语义, 唯一差异: 累加器 acc + product 用 carry-select
//   拆 16+16 位, 关键路径 = 低 16 位加法 + 进位 mux, 不再走 32 位进位链
// =============================================================
module pe_cs #(
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
    output reg  signed [ACC_WIDTH-1:0] acc
);

    // 8x8 signed 乘法 -> 16bit (避免 Icarus $signed 8bit 截断)
    wire signed [2*A_WIDTH-1:0] prod = a_in * b_in;

    // carry-select: acc + prod (32bit + 16bit 符号扩展)
    wire [16:0] lo_ext = acc[15:0] + prod[15:0];
    wire        carry  = lo_ext[16];
    wire [15:0] hi0    = acc[31:16] + {16{prod[15]}};
    wire [15:0] hi1    = acc[31:16] + {16{prod[15]}} + 16'd1;
    wire [31:0] acc_next = {carry ? hi1 : hi0, lo_ext[15:0]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out    <= {A_WIDTH{1'b0}};
            b_out    <= {A_WIDTH{1'b0}};
            en_a_out <= 1'b0;
            en_b_out <= 1'b0;
            acc      <= {ACC_WIDTH{1'b0}};
        end else begin
            a_out    <= a_in;
            b_out    <= b_in;
            en_a_out <= en_a;
            en_b_out <= en_b;
            if (acc_clr)
                acc <= {ACC_WIDTH{1'b0}};
            else if (en_a && en_b)
                acc <= acc_next;
        end
    end

endmodule
