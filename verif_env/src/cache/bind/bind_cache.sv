`include "define.svh"
`ifdef D_CACHE_TEST
bind D_cache cache_debug_interface u_dbg_if(

    //==================内置寄存器======================//
    .valid(valid),
    .tag(tag),
    .cache_data(cache_data),
    .dirty(dirty),
    .curr_state(curr_state),
    .next_state(next_state),
    //==================内置寄存器======================//



    //==================地址分解信号====================//
    .index_in(index_in),
    .tag_in(tag_in),
    .offset_in(offset_in),
    .word_offset(word_offset),
    //==================地址分解信号====================//


    //==================命中控制信号====================//
    .hit_sign(hit_sign),
    .hit_way(hit_way),
    .way_hit(way_hit),
    //==================命中控制信号====================//



    //====================握手信号====================//
    .cpu_req_handshake(cpu_req_handshake),
    .cpu_resp_handshake(cpu_resp_handshake),
    .mem_req_handshake(mem_req_handshake),
    .mem_resp_handshake(mem_resp_handshake),
    //====================握手信号====================//


    //====================替换信号====================//
    .alloc_way(alloc_way),
    .curr_alloc_way(curr_alloc_way),
    .hit_rdata(hit_rdata),
    .alloc_data(alloc_data),
    .alloc_enable_condition(alloc_enable_condition),
    .alloc_enable(alloc_enable),
    .alloc_addr(alloc_addr),
    //====================替换信号====================//


    //====================控制信号====================//
    .is_dirty(is_dirty),
    .is_not_dirty(is_not_dirty),
    .is_write_back(is_write_back),
    .wb_done(wb_done),
    .miss_done(miss_done),
    .write_req_condition(write_req_condition),
    .read_req_condition(read_req_condition),
    .cpu_req_valid_condition(cpu_req_valid_condition),
    .mem_req_valid_condition(mem_req_valid_condition),

    //====================控制信号====================//


    //======================IO======================//
    // 系统时钟与复位
    .clk(clk),
    .reset(reset),
    
    // CPU <-> Cache 接口（读写操作）
    .cpu_req_valid(cpu_req_valid),        // CPU访问请求
    .cpu_wr_en(cpu_wr_en),      // CPU写使能（1=写，0=读）
    .cpu_wdata(cpu_wdata),      // CPU写数据
    .cpu_req_addr(cpu_req_addr),   // CPU访问地址
    .cache_rdata(cache_rdata),    // Cache读数据
    .cpu_req_ready(cpu_req_ready),          // 访问完成信号
    .cpu_resp_valid(cpu_resp_valid),
    .cpu_resp_ready(cpu_resp_ready),

    // Cache -> Memory 请求通道
    .mem_req_valid(mem_req_valid),    // cache to mem request
    .mem_req_ready(mem_req_ready),    // mem to cache ready
    .mem_wr_en(mem_wr_en),        //write/read enable, 1=write, 0=read  
    .mem_addr(mem_addr),         //cache to mem addr\
    .mem_wdata(mem_wdata),


    // Memory -> Cache 响应通道  
    .mem_resp_valid(mem_resp_valid),   // mem to cache response
    .mem_resp_ready(mem_resp_ready),   // cache to mem ready
    .mem_rdata(mem_rdata)
    //======================IO======================//    
);

`endif



`ifdef I_CACHE_TEST
bind I_cache cache_debug_interface u_dbg_if(

    //==================内置寄存器======================//
    .valid(valid),
    .tag(tag),
    .cache_data(cache_data),
    .curr_state(curr_state),
    .next_state(next_state),
    //==================内置寄存器======================//



    //==================地址分解信号====================//
    .index_in(index_in),
    .tag_in(tag_in),
    .offset_in(offset_in),
    .word_offset(word_offset),
    //==================地址分解信号====================//


    //==================命中控制信号====================//
    .hit_sign(hit_sign),
    .hit_way(hit_way),
    .way_hit(way_hit),
    //==================命中控制信号====================//



    //====================握手信号====================//
    .cpu_req_handshake(cpu_req_handshake),
    .cpu_resp_handshake(cpu_resp_handshake),
    .mem_req_handshake(mem_req_handshake),
    .mem_resp_handshake(mem_resp_handshake),
    //====================握手信号====================//


    //====================替换信号====================//
    .alloc_way(alloc_way),
    .curr_alloc_way(curr_alloc_way),
    .hit_rdata(hit_rdata),
    .alloc_data(alloc_data),
    .alloc_enable_condition(alloc_enable_condition),
    .alloc_enable(alloc_enable),
    //====================替换信号====================//


    //====================控制信号====================//
    .mem_req_valid_condition(mem_req_valid_condition),

    //====================控制信号====================//


    //======================IO======================//
    // 系统时钟与复位
    .clk(clk),
    .reset(reset),
    
    // CPU <-> Cache 接口（读写操作）
    .cpu_req_valid(cpu_req_valid),        // CPU访问请求
    .cpu_req_addr(cpu_req_addr),   // CPU访问地址
    .cache_rdata(cache_rdata),    // Cache读数据
    .cpu_req_ready(cpu_req_ready),          // 访问完成信号
    .cpu_resp_valid(cpu_resp_valid),
    .cpu_resp_ready(cpu_resp_ready),

    // Cache -> Memory 请求通道
    .mem_req_valid(mem_req_valid),    // cache to mem request
    .mem_req_ready(mem_req_ready),    // mem to cache ready
    .mem_wr_en(mem_wr_en),        //write/read enable, 1=write, 0=read  
    .mem_addr(mem_addr),         //cache to mem addr\ 

    // Memory -> Cache 响应通道  
    .mem_resp_valid(mem_resp_valid),   // mem to cache response
    .mem_resp_ready(mem_resp_ready),   // cache to mem ready
    .mem_rdata(mem_rdata)
    //======================IO======================//    
);

`endif