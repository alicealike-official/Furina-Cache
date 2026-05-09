`include "define.svh"

interface cache_debug_interface(

    //==================内置寄存器======================//
    input logic valid [`NUM_CACHE_WAY][`NUM_CACHE_SET],
    input logic [`DATA_ADDR_BUS-$clog2(`CACHE_BLOCK_SIZE)-$clog2(`NUM_CACHE_SET)-1:0]
                tag [`NUM_CACHE_WAY][`NUM_CACHE_SET],
    input logic [`DATA_WIDTH-1:0]
                cache_data [`NUM_CACHE_WAY][`NUM_CACHE_SET][`WORDS_PER_BLOCK],
    `ifdef D_CACHE_TEST
    input logic dirty [`NUM_CACHE_WAY][`NUM_CACHE_SET],
    input logic [1:0] curr_state,
    input logic [1:0] next_state,
    `endif 

    `ifdef I_CACHE_TEST
    input logic curr_state,
    input logic next_state,    
    `endif
    //==================内置寄存器======================//



    //==================地址分解信号====================//
    input logic [$clog2(`NUM_CACHE_SET)-1:0]                                        index_in,
    input logic [`DATA_ADDR_BUS-$clog2(`NUM_CACHE_SET)-$clog2(`CACHE_BLOCK_SIZE)-1:0] tag_in,
    input logic [$clog2(`CACHE_BLOCK_SIZE)-1:0]                                     offset_in,
    input logic [$clog2(`WORDS_PER_BLOCK)-1:0]                                      word_offset,
    //==================地址分解信号====================//


    //==================命中控制信号====================//
    input logic hit_sign,
    input logic [$clog2(`NUM_CACHE_WAY)-1:0] hit_way,
    input logic [`NUM_CACHE_WAY-1:0] way_hit,
    //==================命中控制信号====================//



    //====================握手信号====================//
    input logic cpu_req_handshake,
    input logic cpu_resp_handshake,
    input logic mem_req_handshake,
    input logic mem_resp_handshake,
    //====================握手信号====================//


    //====================替换信号====================//
    input logic [$clog2(`NUM_CACHE_WAY)-1:0]
                alloc_way [`NUM_CACHE_SET],
    input logic [$clog2(`NUM_CACHE_WAY)-1:0] curr_alloc_way,
    input logic [`DATA_WIDTH-1:0] hit_rdata,
    input logic [`DATA_WIDTH-1:0] alloc_data,
    input logic alloc_enable_condition,
    input logic [`NUM_CACHE_SET-1:0] alloc_enable,
    `ifdef D_CACHE_TEST
    input logic [`DATA_ADDR_BUS-1:0] alloc_addr,
    `endif
    //====================替换信号====================//


    //====================控制信号====================//
    `ifdef D_CACHE_TEST
    input logic is_dirty,
    input logic is_not_dirty,
    input logic is_write_back,
    input logic wb_done,
    input logic miss_done,
    input logic write_req_condition,
    input logic read_req_condition,
    input logic cpu_req_valid_condition,
    `endif 
    input logic mem_req_valid_condition,

    //====================控制信号====================//


    //======================IO======================//
    // 系统时钟与复位
    input  logic                             clk,
    input  logic                             reset,
    
    // CPU <-> Cache 接口（读写操作）
    input  logic                             cpu_req_valid,        // CPU访问请求
    `ifdef D_CACHE_TEST
    input  logic                             cpu_wr_en,      // CPU写使能（1=写，0=读）
    input  logic [`DATA_WIDTH-1 : 0]           cpu_wdata,      // CPU写数据
    `endif 
    input logic [`DATA_ADDR_BUS-1 : 0]         cpu_req_addr,   // CPU访问地址
    input logic [`DATA_WIDTH-1 : 0]           cache_rdata,    // Cache读数据
    input logic                             cpu_req_ready,          // 访问完成信号
    input logic                             cpu_resp_valid,
    input logic                             cpu_resp_ready,

    // Cache -> Memory 请求通道
    input logic                             mem_req_valid,    // cache to mem request
    input  logic                            mem_req_ready,    // mem to cache ready
    input logic                             mem_wr_en,        //write/read enable, 1=write, 0=read  
    input logic [`DATA_ADDR_BUS-1 : 0]         mem_addr,         //cache to mem addr\
    `ifdef D_CACHE_TEST
    input logic [8*`CACHE_BLOCK_SIZE-1 : 0]  mem_wdata,
    `endif 

    // Memory -> Cache 响应通道  
    input  logic                             mem_resp_valid,   // mem to cache response
    input  logic                             mem_resp_ready,   // cache to mem ready
    input  logic [8*`CACHE_BLOCK_SIZE-1 : 0]  mem_rdata
    //======================IO======================//    
);

endinterface


