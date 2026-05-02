// filename: configurable_delay_mem.sv
`include "define.svh"
module configurable_delay_mem(
    input  wire                             clk,
    input  wire                             rst_n,

    input wire [31:0]                       latency_in,
    
    // Cache接口
    input  wire                             mem_req_valid,
    output wire                             mem_req_ready,
    input  wire                             mem_wr_en,
    input  wire [`DATA_ADDR_BUS - 1:0]      mem_addr,
    input  wire [8*`CACHE_BLOCK_SIZE-1 : 0] mem_wdata,
    output wire                             mem_resp_valid,
    input  wire                             mem_resp_ready,
    output reg  [8*`CACHE_BLOCK_SIZE-1 : 0] mem_rdata
);

    localparam Offset_Width = $clog2(`CACHE_BLOCK_SIZE);
    //====================内存存储体==============================//
    reg [8*`CACHE_BLOCK_SIZE-1 : 0] block_mem [bit [31:0]];
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

    //========================锁存请求信号=========================//
    reg                             mem_wr_en_r;
    reg [`DATA_ADDR_BUS:0]          mem_addr_r;
    reg [8*`CACHE_BLOCK_SIZE-1:0]   mem_wdata_r;
    //========================锁存请求信号=========================//
    
    // 获取块基地址
    function [31:0] get_block_addr(input [31:0] addr);
        return {addr[31:Offset_Width], {Offset_Width{1'b0}}};
    endfunction


    // // 读写函数
    // function [8*`CACHE_BLOCK_SIZE-1 : 0] read_cache_line(input [31:0] addr);
    //     integer i;
    //     reg [31:0] base_addr;
    //     begin
    //         base_addr = {addr[31:$clog2(`CACHE_BLOCK_SIZE)], {$clog2(`CACHE_BLOCK_SIZE){1'b0}}};
    //         for (i = 0; i < `CACHE_BLOCK_SIZE; i = i + 1)
    //             read_cache_line[i*8 +: 8] = memory[base_addr + i];
    //     end
    // endfunction
    
    // function void write_cache_line(input [31:0] addr, input [8*`CACHE_BLOCK_SIZE-1 : 0] data);
    //     integer i;
    //     reg [31:0] base_addr;
    //     begin
    //         base_addr = {addr[31:$clog2(`CACHE_BLOCK_SIZE)], {$clog2(`CACHE_BLOCK_SIZE){1'b0}}};
    //         for (i = 0; i < `CACHE_BLOCK_SIZE; i = i + 1)
    //             memory[base_addr + i] = data[i*8 +: 8];
    //     end
    // endfunction
    
    //===========================状态机跳转===========================//

    always @(*) begin
        case(curr_state) 
            IDLE: begin
                if (mem_req_handshake && current_latency > 0) begin
                    next_state = WAIT;
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

            else if(mem_req_valid && (curr_state == IDLE && latency_in == 0) || (curr_state == WAIT && current_latency == 1)) begin
                mem_resp_valid_r <= 1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            mem_wr_en_r <= 0;
            mem_addr_r <= 0;
            mem_wdata_r <= 0;
        end

        else begin
            if(mem_req_handshake) begin
                mem_wr_en_r <= mem_wr_en;
                mem_addr_r <= mem_addr;
                mem_wdata_r <= mem_wdata;
            end

            if (mem_resp_handshake) begin
                mem_wr_en_r <= 0;
                mem_addr_r <= 0;
                mem_wdata_r <= 0;
            end
        end
    end

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         bit [31:0] i;
    //         for (i = 0; i < MEM_SIZE; i = i + 1) begin
    //             memory[i] <= i[7:0];
    //             //memory[i] <= 0;
    //         end
    //     end

    //     else begin
    //         if (mem_resp_handshake && mem_wr_en_r ) begin
    //             write_cache_line(mem_addr_r, mem_wdata_r);
    //         end
    //     end
    // end

        // ---- 动态内存分配与数据访问（时序逻辑） ----
    always @(posedge clk) begin
        if (mem_req_handshake) begin
            automatic bit [31:0] block_addr = get_block_addr(mem_addr);
            if (!block_mem.exists(block_addr)) begin
                // 块不存在，随机化整块数据
                for (int i = 0; i < `CACHE_BLOCK_SIZE; i++)
                    block_mem[block_addr][i*8 +: 8] = $urandom;
            end
        end

        if (mem_resp_handshake && mem_wr_en_r) begin
            // 写响应：将锁存的整块数据写入
            automatic bit [31:0] block_addr = get_block_addr(mem_addr_r);
            block_mem[block_addr] = mem_wdata_r;
        end
    end

    // 读数据
    wire [31:0] read_block_addr = get_block_addr(mem_addr_r);
    // assign mem_rdata = (mem_resp_valid && !mem_wr_en_r) ?
    //                    block_mem[read_block_addr] : {8*`CACHE_BLOCK_SIZE{1'b0}};

    // reg [8*`CACHE_BLOCK_SIZE-1 : 0] mem_rdata_reg;

    // always @(posedge clk or negedge rst_n) begin
    //     if (!rst_n) begin
    //         mem_rdata_reg <= '0;
    //     end else begin
    //         if (mem_resp_handshake && !mem_wr_en_r) begin
    //             // 在握手成功且为读时，从 block_mem 中读取
    //             mem_rdata_reg <= block_mem[get_block_addr(mem_addr_r)];
    //         end else if (mem_resp_handshake) begin
    //             // 写回时数据无意义，可清零
    //             mem_rdata_reg <= '0;
    //         end
    //         // 其余情况保持
    //     end
    // end

    // assign mem_rdata = mem_rdata_reg;  // 如果端口声明为 wire，改为 output wire，用 assign
    always_comb begin
        if (mem_resp_valid && !mem_wr_en_r) begin
            mem_rdata = block_mem[get_block_addr(mem_addr_r)];
        end
        else begin
            mem_rdata = '0;
        end
    end

    //===========================寄存器更新===========================//

    //============================握手信号=============================//
    assign mem_req_ready = (curr_state == IDLE);
    assign mem_req_handshake = mem_req_valid && mem_req_ready;

    assign mem_resp_valid = mem_resp_valid_r;
    assign mem_resp_handshake = mem_resp_valid && mem_resp_ready;

    //assign mem_rdata = (mem_resp_valid && !mem_wr_en_r) ? read_cache_line(mem_addr_r) : {8*`CACHE_BLOCK_SIZE{1'b0}};

    //for debug
    //assign mem_rdata = (mem_resp_valid && !mem_wr_en) ? {8*`CACHE_BLOCK_SIZE{1'b1}} : {8*`CACHE_BLOCK_SIZE{1'b0}};
endmodule