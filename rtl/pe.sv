// =============================================================
// pe : 脉动阵列处理单元
//   a_in → a_out (寄存1拍, 数据向右流)
//   b_in → b_out (寄存1拍, 数据向下流)
//   en_a & en_b 同时有效时: acc <= acc + a_in * b_in
// =============================================================
module pe (
    input  wire clk,
    input  wire rst_n,
    input  wire signed [7:0]  a_in,
    input  wire signed [7:0]  b_in,
    input  wire        en_a,          // A 通道数据有效标志
    input  wire        en_b,          // B 通道数据有效标志
    output reg  signed [7:0]  a_out,
    output reg  signed [7:0]  b_out,
    output reg         en_a_out,      // 有效标志随数据一起传递
    output reg         en_b_out,
    output reg  signed [31:0] acc     // 本 PE 的部分和 = C[i][j]
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_out    <= 8'sd0;
        b_out    <= 8'sd0;
        en_a_out <= 1'b0;
        en_b_out <= 1'b0;
        acc      <= 32'sd0;
    end else begin
        a_out    <= a_in;              // 数据寄存一拍再传 → 每拍走一格
        b_out    <= b_in;
        en_a_out <= en_a;
        en_b_out <= en_b;
        if (en_a && en_b)              // 两个通道都有效才累加
            acc <= acc + a_in * b_in;
    end
end

endmodule
