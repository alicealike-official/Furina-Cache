`include "define.svh"

interface  cache_interface(
    input clk,
    input rst_n
);
    logic                                   cpu_valid;        // CPU访问请求
    logic                                   cpu_wr_en;      // CPU写使能（1=写，0=读）
    logic   [`DATA_ADDR_BUS-1 : 0]          cpu_req_addr;   // CPU访问地址
    logic   [`DATA_WIDTH-1 : 0]             cpu_wdata;      // CPU写数据
    logic   [`DATA_WIDTH-1 : 0]             cache_rdata;    // Cache读数据
    logic                                   cpu_ready;          // 访问完成信号

    logic                                   mem_req_valid;  // 内存请求
    logic                                   mem_req_ready;  //
    logic                                   mem_wr_en;      // 内存写使能（写回用）
    logic [`DATA_ADDR_BUS-1 : 0]            mem_addr;       // 内存地址
    logic [8*`CACHE_BLOCK_SIZE-1 : 0]       mem_wdata;      // 写回内存的数据
    logic                                   mem_resp_valid;
    logic                                   mem_resp_ready;
    logic [8*`CACHE_BLOCK_SIZE-1 : 0]       mem_rdata;       // 内存读数据

    

    //for debug
    `ifdef DEBUG
    event state_begin_to_driver;
    event state_begin_to_drive;

    event state_begin_to_mon;
    event wait_ready_end_driver;

    logic [1:0] curr_state;
    `endif
endinterface