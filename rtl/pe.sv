// =============================================================
// pe : 脉动阵列处理单元 (参数化位宽)
//   a_in -> a_out (寄存1拍, 数据向右流)
//   b_in -> b_out (寄存1拍, 数据向下流)
//   en 标志随数据同拍传递
//   acc_clr 清零累加器 (优先级高于累加; 转发不冻结)
//   en_a & en_b 同时有效时: acc <= acc + a_in * b_in
//   累加语义镜像 mac.sv: ACC_WIDTH 位 2 补码回绕, 无饱和
// =============================================================
module pe #(
    parameter A_WIDTH   = 8,   // a/b 有符号位宽
    parameter ACC_WIDTH = 32   // 累加器有符号位宽
) (
    input  wire clk,
    input  wire rst_n,
    input  wire acc_clr,        // 累加器清零 (任务边界)
    input  wire signed [A_WIDTH-1:0]  a_in,
    input  wire signed [A_WIDTH-1:0]  b_in,
    input  wire        en_a,          // A 通道数据有效标志
    input  wire        en_b,          // B 通道数据有效标志
    output reg  signed [A_WIDTH-1:0]  a_out,
    output reg  signed [A_WIDTH-1:0]  b_out,
    output reg         en_a_out,      // 有效标志随数据一起传递
    output reg         en_b_out,
    output reg  signed [ACC_WIDTH-1:0] acc   // 本 PE 的部分和 = C[i][j]
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_out    <= {A_WIDTH{1'b0}};
        b_out    <= {A_WIDTH{1'b0}};
        en_a_out <= 1'b0;
        en_b_out <= 1'b0;
        acc      <= {ACC_WIDTH{1'b0}};
    end else begin
        a_out    <= a_in;              // 数据寄存一拍再传 -> 每拍走一格
        b_out    <= b_in;
        en_a_out <= en_a;
        en_b_out <= en_b;
        if (acc_clr)
            acc <= {ACC_WIDTH{1'b0}};  // 清零优先
        else if (en_a && en_b)         // 两个通道都有效才累加
            acc <= acc + a_in * b_in;
    end
end

endmodule
