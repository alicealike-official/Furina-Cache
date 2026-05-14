module axi_master_micro_adapter #(
    parameter AXI_DATA_WIDTH   = 32,   // AXI 数据位宽
    parameter AXI_ADDR_WIDTH   = 32,   // AXI 地址位宽
    parameter AXI_ID_WIDTH     = 4,    // AXI ID 位宽
    parameter AXI_BURST_LEN    = 16,   // 最大突发长度（一拍为单位）
    parameter MAX_OSD          = 4              // 最大未完成事务数
) (
    // ============================================================
    // 
    //                      Transaction                 
    // 
    // ============================================================
    //----------------Transaction control signal----------//
    input  wire                             start_write,    // 启动写突发（脉冲）
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,           // 起始地址
    input  wire [7:0]                       burst_len,      // 突发长度
    input  wire [2:0]                       burst_size,     // 每拍字节数（2^size）
    input  wire [1:0]                       burst_type,     // 突发类型（通常 INCR）
    input  wire [(AXI_DATA_WIDTH/8)-1:0]    write_strb,     // 写掩码
    input  wire [AXI_ID_WIDTH-1:0]          id,             // 事务 ID
    output wire                             wr_req_ready,   // 可以发送下一个请求
    //----------------Transaction control signal----------//



    //----------------Transaction write signal----------//
    input  wire [AXI_DATA_WIDTH-1:0]        wdata_i,        // 写数据逐拍输入
    input  wire                             wdata_valid,    // 当前拍数据有效
    output wire                             wdata_ready,    // 本拍可以接收
    //----------------Transaction write signal----------//


    //----------------Transaction complete signal----------//
    output wire                             write_done,     // 写突发全部完成
    output wire [1:0]                       error_resp,     // 错误响应（暂简单化）
    //----------------Transaction complete signal----------//



    // ============================================================
    // 
    //                      AXI-Interface                 
    // 
    // ============================================================
    //--------Clock and Reset-------//
    input  wire                             axi_aclk,
    input  wire                             axi_aresetn,
    //--------Clock and Reset-------//



    //--------AW Channel-------//
    output wire [AXI_ID_WIDTH-1:0]          m_axi_awid,
    output wire [AXI_ADDR_WIDTH-1:0]        m_axi_awaddr,
    output wire [7:0]                       m_axi_awlen,
    output wire [2:0]                       m_axi_awsize,
    output wire [1:0]                       m_axi_awburst,
    output wire                             m_axi_awlock,
    output wire [3:0]                       m_axi_awcache,
    output wire [2:0]                       m_axi_awprot,
    output wire [3:0]                       m_axi_awqos,
    output wire [3:0]                       m_axi_awregion,
    output wire                             m_axi_awvalid,
    input  wire                             m_axi_awready,
    //--------AW Channel-------//



    //--------W Channel-------//
    output wire [AXI_DATA_WIDTH-1:0]        m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0]    m_axi_wstrb,
    output wire                             m_axi_wlast,
    output wire                             m_axi_wvalid,
    input  wire                             m_axi_wready,
    //--------W Channel-------//



    //--------B Channel-------//
    input  wire [AXI_ID_WIDTH-1:0]          m_axi_bid,
    input  wire [1:0]                       m_axi_bresp,
    input  wire                             m_axi_bvalid,
    output wire                             m_axi_bready,
    //--------B Channel-------//
);

    localparam AXI_AWCACHE  = 4'b0011;
    localparam AXI_AWPROT   = 3'b000;
    localparam AXI_AWLOCK   = 1'b0;
    localparam AXI_AWQOS    = 4'h0;
    localparam AXI_AWREGION = 4'h0;

    

endmodule