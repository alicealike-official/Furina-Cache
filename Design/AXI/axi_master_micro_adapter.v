module axi_master_micro_adapter #(
    parameter AXI_DATA_WIDTH   = 32,   // AXI 数据位宽
    parameter AXI_ADDR_WIDTH   = 32,   // AXI 地址位宽
    parameter AXI_ID_WIDTH     = 4,    // AXI ID 位宽
    parameter AXI_BURST_LEN    = 16,    // 最大突发长度（一拍为单位）
    parameter MAX_OSD          = 4
) (
    //====================Transaction Region==================//
    //----------------Transaction control signal----------//
    input  wire                             rd_req_valid,     // 启动读突发（脉冲）
    input  wire                             wr_req_valid,    // 启动写突发（脉冲）
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,           // 起始地址
    input  wire [7:0]                       burst_len,      // 突发长度
    input  wire [2:0]                       burst_size,     // 每拍字节数（2^size）
    input  wire [1:0]                       burst_type,     // 突发类型（通常 INCR）
    input  wire [(AXI_DATA_WIDTH/8)-1:0]    write_strb,
    input  wire [AXI_ID_WIDTH-1:0]          id,             // 事务 ID
    output wire                             rd_req_ready,
    output wire                             wr_req_ready,
    //----------------Transaction control signal----------//



    //----------------Transaction write signal----------//
    input  wire [AXI_DATA_WIDTH-1:0]        wdata_i,        // 写数据逐拍输入
    input  wire                             wdata_valid,    // 当前拍数据有效
    output wire                             wdata_ready,    // 本拍可以接收
    //----------------Transaction write signal----------//




    //----------------Transaction read signal----------//
    output wire [AXI_DATA_WIDTH-1:0]        rdata_o,        // 读数据逐拍输出
    output wire                             rdata_valid,    // 当前拍数据有效
    input  wire                             rdata_ready,    // 本拍已取走
    //----------------Transaction read signal----------//


    //----------------Transaction complete signal----------//
    output wire                             read_done,      // 读突发全部完成
    output wire                             write_done,     // 写突发全部完成
    output wire [1:0]                       error_resp,     // 错误响应（暂简单化）
    //----------------Transaction complete signal----------//



    // ============================ AXI Interface ====================//
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




    //--------AR Channel-------//
    output wire [AXI_ID_WIDTH-1:0]          m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0]        m_axi_araddr,
    output wire [7:0]                       m_axi_arlen,
    output wire [2:0]                       m_axi_arsize,
    output wire [1:0]                       m_axi_arburst,
    output wire                             m_axi_arlock,
    output wire [2:0]                       m_axi_arprot,
    output wire [3:0]                       m_axi_arqos,
    output wire [3:0]                       m_axi_arregion,
    output wire [3:0]                       m_axi_arcache,
    output wire                             m_axi_arvalid,
    input  wire                             m_axi_arready,
    //--------AR Channel-------//



    //--------R Channel-------//
    input  wire [AXI_ID_WIDTH-1:0]          m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]        m_axi_rdata,
    input  wire [1:0]                       m_axi_rresp,
    input  wire                             m_axi_rlast,
    input  wire                             m_axi_rvalid,
    output wire                             m_axi_rready
    //--------R Channel-------//

);

    wire [1:0] wr_error_resp;
    wire [1:0] rd_error_resp;

    // ================================================================
    //  axi_master_micro_write_adapter 例化
    // ================================================================
    axi_master_micro_write_adapter #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_BURST_LEN  (AXI_BURST_LEN),
        .MAX_OSD        (MAX_OSD)
    ) u_write (
        // ---- 事务侧 ----
        .wr_req_valid   (wr_req_valid),
        .addr           (addr),
        .burst_len      (burst_len),
        .burst_size     (burst_size),
        .burst_type     (burst_type),
        .id             (id),
        .wr_req_ready   (wr_req_ready),
        .write_strb     (write_strb),
        .wdata_i        (wdata_i),
        .wdata_valid    (wdata_valid),
        .wdata_ready    (wdata_ready),
        .write_done     (write_done),
        .error_resp     (wr_error_resp),
        // ---- AXI 侧 ----
        .axi_aclk       (axi_aclk),
        .axi_aresetn    (axi_aresetn),
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awqos    (m_axi_awqos),
        .m_axi_awregion (m_axi_awregion),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready)
    );
    // ================================================================
    //  axi_master_micro_read_adapter 例化
    // ================================================================
    axi_master_micro_read_adapter #(
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_BURST_LEN  (AXI_BURST_LEN),
        .MAX_OSD        (MAX_OSD)
    ) u_read (
        // ---- 事务侧 ----
        .rd_req_valid   (rd_req_valid),
        .addr           (addr),
        .burst_len      (burst_len),
        .burst_size     (burst_size),
        .burst_type     (burst_type),
        .id             (id),
        .rd_req_ready   (rd_req_ready),
        .rdata_o        (rdata_o),
        .rdata_valid    (rdata_valid),
        .rdata_ready    (rdata_ready),
        .read_done      (read_done),
        .error_resp     (rd_error_resp),
        // ---- AXI 侧 ----
        .axi_aclk       (axi_aclk),
        .axi_aresetn    (axi_aresetn),
        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arqos    (m_axi_arqos),
        .m_axi_arregion (m_axi_arregion),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );
    // ================================================================
    //  error_resp 合并
    // ================================================================
    assign error_resp = wr_error_resp | rd_error_resp;

endmodule