`include "define.svh"

interface  cache_interface(
    input clk,
    input rst_n
);
    //cpu-cache握手信号
    logic                                   cpu_req_valid;  
    logic                                   cpu_req_ready; 
    logic                                   cpu_resp_valid;
    logic                                   cpu_resp_ready;

    
    logic                                   cpu_wr_en;      // CPU写使能（1=写，0=读）
    logic   [`DATA_ADDR_BUS-1 : 0]          cpu_req_addr;   // CPU访问地址
    logic   [`DATA_WIDTH-1 : 0]             cpu_wdata;      // CPU写数据
    logic   [`DATA_WIDTH-1 : 0]             cache_rdata;    // Cache读数据
 

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
    event state_begin_to_drive;

    event cpu_in_monitor_evt;
    event cache_out_monitor_evt;
    event mem_req_monitor_evt;
    event mem_rsp_monitor_evt;

    event wait_ready_end_driver;
    event begin_to_compare;

    logic [1:0] curr_state;
    `endif
endinterface