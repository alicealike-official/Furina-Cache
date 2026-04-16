interface  cache_interface(
    input clk,
    input rst_n
);
    logic                               cpu_req,        // CPU访问请求
    logic                               cpu_wr_en,      // CPU写使能（1=写，0=读）
    logic   [DataAddrBus-1 : 0]         cpu_req_addr,   // CPU访问地址
    logic   [DataWidth-1 : 0]           cpu_wdata,      // CPU写数据
    logic   [DataWidth-1 : 0]           cache_rdata,    // Cache读数据
    logic                               ready,          // 访问完成信号

    logic                             mem_req,        // 内存请求
    logic                             mem_wr_en,      // 内存写使能（写回用）
    logic [DataAddrBus-1 : 0]         mem_addr,       // 内存地址
    logic [8*Cache_Block_Size-1 : 0]  mem_wdata,      // 写回内存的数据
    logic                             mem_resp,       // 内存响应
    logic [8*Cache_Block_Size-1 : 0]  mem_rdata       // 内存读数据
endinterface