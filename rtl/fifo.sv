// =============================================================
// fifo : 同步 valid/ready FIFO, WIDTH x DEPTH, parameterized
//   限制: DEPTH 必须为 2 的幂且 >= 2 (计数器法判满空; DEPTH=1 地址位宽非法)
//   协议: push = wr_valid && wr_ready; pop = rd_valid && rd_ready
//         rd_valid = !empty, wr_ready = !full
//   满时拒绝写 (wr_ready=0), 空时无数据可读 (rd_valid=0)
//   同拍读写: 满态可读不可写 (pop 让出空间后下拍可写)
//   复位: 指针/计数清零 (逻辑清空, 存储阵列内容不清但不可见)
// =============================================================
module fifo #(
    parameter WIDTH = 8,        // 数据位宽
    parameter DEPTH = 16        // FIFO 深度 (必须为 2 的幂, >= 2)
) (
    input  wire clk,
    input  wire rst_n,
    input  wire wr_valid,
    output wire wr_ready,
    input  wire [WIDTH-1:0] wr_data,
    output wire rd_valid,
    input  wire rd_ready,
    output reg  [WIDTH-1:0] rd_data,
    output wire full,
    output wire empty
);

localparam ADDRW = $clog2(DEPTH);

reg [WIDTH-1:0] mem [0:DEPTH-1];
reg [ADDRW-1:0] wr_ptr;
reg [ADDRW-1:0] rd_ptr;
reg [ADDRW:0]   cnt;

wire push = wr_valid && !full;
wire pop  = rd_valid && rd_ready;

assign wr_ready = !full;
assign rd_valid = !empty;
assign full  = (cnt == DEPTH);
assign empty = (cnt == 0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr <= {ADDRW{1'b0}};
        rd_ptr <= {ADDRW{1'b0}};
        cnt    <= {(ADDRW+1){1'b0}};
    end else begin
        if (push) begin
            mem[wr_ptr] <= wr_data;
            wr_ptr      <= wr_ptr + 1'b1;
        end
        if (pop) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
        case ({push, pop})
            2'b10: cnt <= cnt + 1'b1;
            2'b01: cnt <= cnt - 1'b1;
            default: cnt <= cnt;
        endcase
    end
end

always @(*) begin
    if (!empty)
        rd_data = mem[rd_ptr];
    else
        rd_data = {WIDTH{1'b0}};
end

endmodule
