// =============================================================
// fifo : synchronous FIFO, WIDTH x DEPTH, parameterized
// =============================================================
module fifo #(
    parameter WIDTH = 8,        // 数据位宽
    parameter DEPTH = 16        // FIFO 深度 (必须为 2 的幂)
) (
    input  wire        clk, //时钟，每跳变一次电路"走一步"
    input  wire        rst_n,  //复位（低电平有效）
    input  wire        wr_en,  //写使能 =1 时表示"我要写入数据"
    input  wire        rd_en,  //读使能 =1 时表示"我要读取数据"
    input  wire [WIDTH-1:0] wr_data, //要写进去的数据
    output reg  [WIDTH-1:0] rd_data,  //读出来的数据
    output wire        full,  //满了，不能再写
    output wire        empty
);

// ---------------- internal signals ----------------
localparam ADDRW = $clog2(DEPTH);   // 地址位宽: 16→4, 8→3, 自动算

reg [WIDTH-1:0] mem [0:DEPTH-1];    // 寄存器阵列 (RAM)
reg [ADDRW-1:0] wr_ptr;             // 写指针
reg [ADDRW-1:0] rd_ptr;             // 读指针
reg [ADDRW:0]   cnt;                // 计数, 0~DEPTH (多1位表示"满")

// ---------------- write logic ----------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr <= {ADDRW{1'b0}};
    end else if (wr_en && !full) begin
        mem[wr_ptr] <= wr_data;          // 写数据到当前写指针位置
        wr_ptr      <= wr_ptr + 1'b1;    // 写指针 +1 (3位自动回绕 7->0)
    end
end

// ---------------- read logic ----------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr <= {ADDRW{1'b0}};
    end else if (rd_en && !empty) begin
        rd_ptr <= rd_ptr + 1'b1;         // 读指针 +1
    end
end

// ---------------- element counter ----------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt <= {(ADDRW+1){1'b0}};
    end else begin
        case ({wr_en && !full, rd_en && !empty})
            2'b10: cnt <= cnt + 1'b1;    // 只写: cnt+1
            2'b01: cnt <= cnt - 1'b1;    // 只读: cnt-1
            default: cnt <= cnt;         // 同时读写 or 都不动: 不变
        endcase
    end
end

// ---------------- status flags ----------------
assign full  = (cnt == DEPTH);           // 8 个单元全满
assign empty = (cnt == 0);               // 无数据

// ---------------- read data output ----------------
// 组合直出: empty 时输出清零 (rd_en 上升沿时 rd_ptr 尚未更新, 输出的是旧数据)
always @(*) begin
    if (!empty)
        rd_data = mem[rd_ptr];
    else
        rd_data = {WIDTH{1'b0}};
end

endmodule
