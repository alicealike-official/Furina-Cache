// filename: configurable_delay_mem.sv
module configurable_delay_mem #(
    parameter MEM_SIZE       = 1024 * 1024,
    parameter Cache_Block_Size = 64
) (
    input  wire                             clk,
    input  wire                             rst_n,

    input wire [31:0]                       latency_in,
    
    // Cache接口
    input  wire                             mem_req,
    input  wire                             mem_wr_en,
    input  wire [31:0]                      mem_addr,
    input  wire [8*Cache_Block_Size-1 : 0]  mem_wdata,
    output wire                             mem_resp,
    output wire [8*Cache_Block_Size-1 : 0]  mem_rdata
);

    //==================================================
    // 内存存储体
    //==================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    
    //==================================================
    // 可配置延迟控制
    //==================================================
    reg [31:0] current_latency;      // 当前访问延迟
  
    //==================================================
    // 访问状态机（支持随机延迟）
    //==================================================
    localparam IDLE   = 1'b0;
    localparam WAIT   = 1'b1;
    
    reg curr_state;
    reg next_state;
    
    // 读写函数（同之前）
    function [8*Cache_Block_Size-1 : 0] read_cache_line(input [31:0] addr);
        integer i;
        reg [31:0] base_addr;
        begin
            base_addr = {addr[31:$clog2(Cache_Block_Size)], {$clog2(Cache_Block_Size){1'b0}}};
            for (i = 0; i < Cache_Block_Size; i = i + 1)
                read_cache_line[i*8 +: 8] = memory[base_addr + i];
        end
    endfunction
    
    function void write_cache_line(input [31:0] addr, input [8*Cache_Block_Size-1 : 0] data);
        integer i;
        reg [31:0] base_addr;
        begin
            base_addr = {addr[31:$clog2(Cache_Block_Size)], {$clog2(Cache_Block_Size){1'b0}}};
            for (i = 0; i < Cache_Block_Size; i = i + 1)
                memory[base_addr + i] = data[i*8 +: 8];
        end
    endfunction
    
    //==================================================
    // 状态机实现
    //==================================================

    always @(*) begin
        case(curr_state) 
            IDLE: begin
                if (mem_req) begin
                    if((current_latency == 0)) begin
                        next_state = IDLE;
                    end
                    else begin
                        next_state = WAIT;
                    end
                end

                else begin
                    next_state = IDLE;
                end
            end

            WAIT: begin
                if (current_latency == 0) begin
                    next_state = IDLE;
                end

                else begin
                    next_state = WAIT;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= IDLE;
            current_latency <= latency_in;
        end

        else begin
            curr_state <= next_state;
            if (curr_state == WAIT && current_latency > 0) begin
                current_latency <= current_latency-1;
            end

            if (mem_req && curr_state == IDLE && latency_in != 0) begin
                current_latency <= latency_in;
            end

            if (mem_resp && mem_wr_en ) begin
                write_cache_line(mem_addr, mem_wdata);
            end
        end
    end

    assign mem_resp = mem_req && ((curr_state == IDLE && current_latency == 0) || 
                                    (curr_state == WAIT && current_latency == 1));

    assign mem_rdata = (mem_resp && !mem_wr_en) ? read_cache_line(mem_addr) : {8*Cache_Block_Size{1'b0}};
endmodule