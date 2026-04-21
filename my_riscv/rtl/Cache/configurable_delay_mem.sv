// filename: configurable_delay_mem.sv
module configurable_delay_mem #(
    parameter MEM_SIZE       = 1024*1024,
    parameter Cache_Block_Size = 64
) (
    input  wire                             clk,
    input  wire                             rst_n,

    input wire [31:0]                       latency_in,
    
    // Cache接口
    input  wire                             mem_req_valid,
    output wire                             mem_req_ready,
    input  wire                             mem_wr_en,
    input  wire [31:0]                      mem_addr,
    input  wire [8*Cache_Block_Size-1 : 0]  mem_wdata,
    output wire                             mem_resp_valid,
    input  wire                             mem_resp_ready,
    output wire [8*Cache_Block_Size-1 : 0]  mem_rdata
);

    //====================内存存储体==============================//
    reg [7:0] memory [0:MEM_SIZE];
    //====================内存存储体==============================//



    //=======================可配置延迟控制===========================//
    reg [31:0] current_latency;      // 当前访问延迟
    //=======================可配置延迟控制===========================//
  


    //========================状态机定义==========================//
    localparam IDLE   = 1'b0;
    localparam WAIT   = 1'b1;
    
    reg curr_state;
    reg next_state;
    //========================状态机定义==========================//

    wire mem_resp_handshake;
    wire mem_req_handshake;

    
    // 读写函数
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
    
    //===========================状态机跳转===========================//

    always @(*) begin
        case(curr_state) 
            IDLE: begin
                if (mem_req_handshake) begin
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
    //===========================状态机跳转===========================//

    //===========================寄存器更新===========================//
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            curr_state <= IDLE;
        end

        else begin
            curr_state <= next_state;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_latency <= latency_in;
        end

        else begin
            if (curr_state == WAIT && current_latency > 0) begin
                current_latency <= current_latency-1;
            end

            else if (mem_req_handshake && curr_state == IDLE && latency_in != 0) begin
                current_latency <= latency_in;
            end

            else begin
                current_latency <= current_latency;
            end
        end
    end

    reg mem_resp_valid_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_resp_valid_r <= 0;
        end

        else begin
            if (mem_resp_handshake) begin
                mem_resp_valid_r <= 0;
            end

            else if((curr_state == IDLE && latency_in == 0) || (curr_state == WAIT && current_latency == 1)) begin
                mem_resp_valid_r <= 1;
            end

            else begin
                mem_resp_valid_r <= mem_resp_valid_r;
            end
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integer i;
            for (i = 0; i < MEM_SIZE; i = i + 1) begin
                memory[i] <= 8'b0;
            end
        end

        else begin
            if (mem_resp_handshake && mem_wr_en ) begin
                write_cache_line(mem_addr, mem_wdata);
            end
        end
    end
    //===========================寄存器更新===========================//

    //============================握手信号=============================//
    assign mem_req_ready = (curr_state == IDLE);
    assign mem_req_handshake = mem_req_valid && mem_req_ready;

    assign mem_resp_valid = mem_resp_valid_r;
    assign mem_resp_handshake = mem_resp_valid && mem_resp_ready;

    assign mem_rdata = (mem_resp_valid && !mem_wr_en) ? read_cache_line(mem_addr) : {8*Cache_Block_Size{1'b0}};

    //for debug
    //assign mem_rdata = (mem_resp_valid && !mem_wr_en) ? {8*Cache_Block_Size{1'b1}} : {8*Cache_Block_Size{1'b0}};
endmodule