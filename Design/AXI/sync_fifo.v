// ============================================================
// 文件名   : sync_fifo.v
// 作者     : alicealike
// 日期     : 2026-05-13
// 描述     : 同步fifo
// 版本     : 1.0
// 修改记录 :
//   2026-05-13  alicealike  - 创建
// ============================================================


module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 16       
) (
    input  wire                   clk,
    input  wire                   rst_n,      

    // write
    input  wire [DATA_WIDTH-1:0]  wr_data,
    input  wire                   wr_en,
    output wire                   full,

    // read
    output wire [DATA_WIDTH-1:0]  rd_data,
    input  wire                   rd_en,
    output wire                   empty
);
    localparam ADDR_WIDTH = $clog2(DEPTH);

    reg  [DATA_WIDTH-1:0]   mem [0:DEPTH-1];
    reg  [ADDR_WIDTH:0]     wr_ptr, rd_ptr;   // 多一位用于判断空满
    wire                    wr_toggle;
    wire                    rd_toggle;
    wire [ADDR_WIDTH:0]     next_wr_ptr;
    wire [ADDR_WIDTH:0]     next_rd_ptr;

    assign wr_toggle = wr_ptr[ADDR_WIDTH];
    assign rd_toggle = rd_ptr[ADDR_WIDTH];
    assign next_wr_ptr = (wr_en && !full) ? wr_ptr + 1'b1 : wr_ptr;
    assign next_rd_ptr = (rd_en && !empty) ? rd_ptr + 1'b1 : rd_ptr;


    assign full  = (next_wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]) && 
                   (next_wr_ptr[ADDR_WIDTH]      != rd_toggle);
    assign empty = (wr_ptr == rd_ptr);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end 
        
        else begin
            wr_ptr <= next_wr_ptr;
            rd_ptr <= next_rd_ptr;
        end
    end


    always @(posedge clk) begin
        if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    // 读数据（first-word fall-through：读使能后下一个周期数据有效）
    reg [DATA_WIDTH-1:0] rd_data_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_reg <= 0;
        end

        else begin
            if (rd_en && !empty) begin
                rd_data_reg <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            end
        end
    end
    assign rd_data = rd_data_reg;

endmodule