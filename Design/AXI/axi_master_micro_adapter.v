module axi_master_micro_adapter #(
    parameter AXI_DATA_WIDTH   = 32,   // AXI 数据位宽
    parameter AXI_ADDR_WIDTH   = 32,   // AXI 地址位宽
    parameter AXI_ID_WIDTH     = 4,    // AXI ID 位宽
    parameter AXI_BURST_LEN    = 16    // 最大突发长度（一拍为单位）
) (
    //====================Transaction Region==================//
    //----------------Transaction control signal----------//
    input  wire                             start_read,     // 启动读突发（脉冲）
    input  wire                             start_write,    // 启动写突发（脉冲）
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,           // 起始地址
    input  wire [7:0]                       burst_len,      // 突发长度
    input  wire [2:0]                       burst_size,     // 每拍字节数（2^size）
    input  wire [1:0]                       burst_type,     // 突发类型（通常 INCR）
    input  wire [(AXI_DATA_WIDTH/8)-1:0]    write_strb,
    input  wire [AXI_ID_WIDTH-1:0]          id,             // 事务 ID
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
    // ==============================
    //  AXI 固定配置 (事务侧未暴露)
    // ==============================
    localparam AXI_AWCACHE  = 4'b0011;  // normal non-cacheable bufferable
    localparam AXI_AWPROT   = 3'b000;   // unprivileged, secure, data
    localparam AXI_AWLOCK   = 1'b0;     // normal access
    localparam AXI_AWQOS    = 4'h0;
    localparam AXI_AWREGION = 4'h0;



    //==========状态机定义==========//
    // W Channel
    localparam W_IDLE   = 2'b00;
    localparam W_AW     = 2'b01;
    localparam W_DATA   = 2'b10;
    localparam W_BRESP  = 2'b11;

    // R Channel
    localparam R_IDLE   = 2'b00;
    localparam R_AR     = 2'b01;
    localparam R_DATA   = 2'b10;
    //==========状态机定义==========//

    //==========状态机寄存器==========//
    reg [1:0] w_curr_state;
    reg [1:0] w_next_state;

    reg [1:0] r_curr_state;
    reg [1:0] r_next_state;
    //==========状态机寄存器==========//

    //==========握手信号定义==========//
    wire w_aw_handshake;
    wire w_w_handshake;
    wire w_b_handshake;
    wire r_ar_handshake;
    wire r_r_handshake;
    //==========握手信号定义==========//

    //==========流程控制信号定义==========//
    wire w_data_done;
    wire r_data_done;
    wire m_axi_awvalid_up;
    wire m_axi_awvalid_down;
    wire m_axi_wvalid_ctl;
    wire m_axi_wvalid_disctl;

    wire m_axi_arvalid_up;
    wire m_axi_arvalid_down;
    //==========流程控制信号定义==========//

    //==========输出寄存器定义(AW)==========//
    reg [AXI_ID_WIDTH-1:0]          m_axi_awid_r;
    reg [AXI_ADDR_WIDTH-1:0]        m_axi_awaddr_r;
    reg [7:0]                       m_axi_awlen_r;
    reg [2:0]                       m_axi_awsize_r;
    reg [1:0]                       m_axi_awburst_r;
    reg                             m_axi_awvalid_r;
    //==========输出寄存器定义(AW)==========//


    //==========输出寄存器定义(W)==========//
    reg [AXI_DATA_WIDTH-1:0]        m_axi_wdata_r;
    reg [(AXI_DATA_WIDTH/8)-1:0]    m_axi_wstrb_r;
    reg                             m_axi_wlast_r;
    reg                             m_axi_wvalid_r;
    //==========输出寄存器定义(W)==========//


    //==========输出寄存器定义(AR)==========//
    reg [AXI_ID_WIDTH-1:0]          m_axi_arid_r;
    reg [AXI_ADDR_WIDTH-1:0]        m_axi_araddr_r;
    reg [7:0]                       m_axi_arlen_r;
    reg [2:0]                       m_axi_arsize_r;
    reg [1:0]                       m_axi_arburst_r;
    reg                             m_axi_arvalid_r;
    //==========输出寄存器定义(AR)==========//

    //-----------------------rdata_valid-----------------------//
    reg rdata_valid_r;
    //-----------------------rdata_valid-----------------------//


    //-----------------------counter-----------------------//
    reg [7:0] w_beat_cnt;
    reg [7:0] r_beat_cnt;
    //-----------------------counter-----------------------//



    // ============================================================
    // 
    //                      输出连线                 
    // 
    // ============================================================

    //-----------------------AW-----------------------//
    assign m_axi_awid    = m_axi_awid_r;
    assign m_axi_awaddr  = m_axi_awaddr_r;
    assign m_axi_awlen   = m_axi_awlen_r; 
    assign m_axi_awsize  = m_axi_awsize_r;
    assign m_axi_awburst = m_axi_awburst_r;

    assign m_axi_awlock = AXI_AWLOCK;
    assign m_axi_awcache = AXI_AWCACHE;
    assign m_axi_awprot = AXI_AWPROT;
    assign m_axi_awqos = AXI_AWQOS;
    assign m_axi_awregion = AXI_AWREGION;

    assign m_axi_awvalid  = m_axi_awvalid_r;
    //-----------------------AW-----------------------//


    //-----------------------W-----------------------//
    assign m_axi_wdata   = m_axi_wdata_r;
    assign m_axi_wstrb   = m_axi_wstrb_r;
    assign m_axi_wlast   = m_axi_wlast_r;

    assign m_axi_wvalid   = m_axi_wvalid_r;
    //-----------------------W-----------------------//


    //-----------------------AR-----------------------//
    assign m_axi_arid    = m_axi_arid_r;
    assign m_axi_araddr  = m_axi_araddr_r;
    assign m_axi_arlen   = m_axi_arlen_r;
    assign m_axi_arsize  = m_axi_arsize_r;
    assign m_axi_arburst = m_axi_arburst_r;

    assign m_axi_arlock = AXI_AWLOCK;
    assign m_axi_arcache = AXI_AWCACHE;
    assign m_axi_arprot = AXI_AWPROT;
    assign m_axi_arqos = AXI_AWQOS;
    assign m_axi_arregion = AXI_AWREGION;
      
    assign m_axi_arvalid  = m_axi_arvalid_r;
    //-----------------------AR-----------------------//


    //-----------------------R/B ready-----------------------//
    assign m_axi_bready = (w_curr_state == W_DATA && w_data_done) || (w_curr_state == W_BRESP);
    assign m_axi_rready = (r_curr_state == R_AR && r_ar_handshake) || (r_curr_state == R_DATA && rdata_ready); 
    //-----------------------R/B ready-----------------------//


    //-----------------------trans signal-----------------------//
    assign wdata_ready  = (w_curr_state == W_AW && w_aw_handshake) || (w_curr_state == W_DATA && ~w_w_handshake);   
    assign rdata_o      = m_axi_rdata;        
    assign rdata_valid  = rdata_valid_r;    
    assign read_done    = (r_curr_state == R_DATA && r_r_handshake);      
    assign write_done   = (w_curr_state == W_DATA && w_w_handshake);     
    assign error_resp   = 0;     


    //-----------------------trans signal-----------------------//




    // ============================================================
    // 
    //                      控制信号连线                 
    // 
    // ============================================================
    assign w_aw_handshake = m_axi_awvalid && m_axi_awready;
    assign w_w_handshake  = m_axi_wvalid  && m_axi_wready;
    assign w_b_handshake = m_axi_bvalid && m_axi_bready;
    assign w_data_done = w_w_handshake && (w_beat_cnt == m_axi_awlen_r);


    assign r_ar_handshake = m_axi_arvalid &&m_axi_arready;
    assign r_r_handshake = m_axi_rvalid && m_axi_rready;
    assign r_data_done = r_r_handshake &&(r_beat_cnt == m_axi_arlen_r);

    assign m_axi_awvalid_up = (w_curr_state == W_IDLE && start_write);
    assign m_axi_awvalid_down = (w_curr_state == W_AW && w_aw_handshake);

    assign m_axi_wvalid_ctl = (w_curr_state == W_AW && w_aw_handshake) || 
                            (w_curr_state == W_DATA && ~w_data_done);
    assign m_axi_wvalid_disctl = (w_curr_state == W_DATA && w_data_done);

    assign m_axi_arvalid_up = (r_curr_state == R_IDLE && start_read);
    assign m_axi_arvalid_down = (r_curr_state == R_AR && r_ar_handshake);



    // ============================================================
    // 
    //                      寄存器逻辑                 
    // 
    // ============================================================


    //========================状态机跳转========================//
    always@(*) begin
        case(w_curr_state)
            W_IDLE :   w_next_state = start_write       ? W_AW      : W_IDLE;
            W_AW   :   w_next_state = w_aw_handshake    ? W_DATA    : W_AW;
            W_DATA :   w_next_state = w_data_done       ? W_BRESP   : W_DATA;
            W_BRESP:   w_next_state = w_b_handshake     ? W_IDLE    : W_BRESP;
            default:   w_next_state = W_IDLE;
        endcase
    end

    always@(*) begin
        case(r_curr_state)
            R_IDLE  :   r_next_state = start_read       ? R_AR   : R_IDLE;
            R_AR    :   r_next_state = r_ar_handshake   ? R_DATA : R_AR;
            R_DATA  :   r_next_state = r_data_done      ? R_IDLE : R_DATA;
            default :   r_next_state = R_IDLE;    
        endcase
    end

    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            w_curr_state <= W_IDLE;
            r_curr_state <= R_IDLE;
        end

        else begin
            w_curr_state <= w_next_state;
            r_curr_state <= r_next_state;
        end
    end
    //========================状态机跳转========================//




    //========================valid寄存器========================//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            m_axi_wvalid_r  <= 0;
            m_axi_awvalid_r <= 0;
            m_axi_arvalid_r <= 0;

            rdata_valid_r   <= 0;
        end

        else begin
            // aw chanel
            if (m_axi_awvalid_up) begin
                m_axi_awvalid_r <= 1;
            end

            if (m_axi_awvalid_down) begin
                m_axi_awvalid_r <= 0;
            end

            //w channel
            if (m_axi_wvalid_ctl) begin
                m_axi_wvalid_r <= wdata_valid;
            end

            if (m_axi_wvalid_disctl) begin
                m_axi_wvalid_r <= 0;
            end

            // ar channel
            if (m_axi_arvalid_up) begin
                m_axi_arvalid_r <= 1;
            end

            if (m_axi_arvalid_down) begin
                m_axi_arvalid_r <= 0;
            end

            //r valid
            if (r_curr_state == R_AR && r_ar_handshake) begin
                rdata_valid_r <= 1;
            end

            if (rdata_valid && rdata_ready && (r_beat_cnt == m_axi_arlen_r)) begin
                rdata_valid_r <= 0;
            end
        end
    end
    //========================valid寄存器========================//



    //-----------------------AW-----------------------//
    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            m_axi_awid_r    <= {AXI_ID_WIDTH{1'b0}};
            m_axi_awaddr_r  <= {AXI_ADDR_WIDTH{1'b0}};
            m_axi_awlen_r   <= 8'd0;
            m_axi_awsize_r  <= 3'd0;
            m_axi_awburst_r <= 2'd0;
        end 
        
        else if (start_write && w_curr_state == W_IDLE) begin
            m_axi_awid_r    <= id;
            m_axi_awaddr_r  <= addr;
            m_axi_awlen_r   <= burst_len;
            m_axi_awsize_r  <= burst_size;
            m_axi_awburst_r <= burst_type;
        end
    end
    //-----------------------AW-----------------------//



    //-----------------------W-----------------------//
    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            m_axi_wdata_r   <= {AXI_DATA_WIDTH{1'b0}};
            m_axi_wstrb_r   <= {(AXI_DATA_WIDTH/8){1'b0}};
            m_axi_wlast_r   <= 1'b0;
        end 

        else if (w_curr_state == W_DATA && m_axi_wvalid) begin
            m_axi_wdata_r   <= wdata_i;
            m_axi_wstrb_r   <= write_strb;
            m_axi_wlast_r   <= (w_beat_cnt == m_axi_awlen_r-1); //最后一个数据传输时拉高
        end
    end
    //-----------------------W-----------------------//



    //-----------------------AR-----------------------//
    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            m_axi_arid_r    <= {AXI_ID_WIDTH{1'b0}};
            m_axi_araddr_r  <= {AXI_ADDR_WIDTH{1'b0}};
            m_axi_arlen_r   <= 8'd0;
            m_axi_arsize_r  <= 3'd0;
            m_axi_arburst_r <= 2'd0;
        end 
        
        else if (start_read && r_curr_state == R_IDLE) begin
            m_axi_arid_r    <= id;
            m_axi_araddr_r  <= addr;
            m_axi_arlen_r   <= burst_len;
            m_axi_arsize_r  <= burst_size;
            m_axi_arburst_r <= burst_type;
        end
    end
    //-----------------------AR-----------------------//


    //-----------------------counter-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            w_beat_cnt <= 8'b0;
            r_beat_cnt <= 8'b0;
        end

        else begin
            if (start_write && w_curr_state == W_IDLE) begin
                w_beat_cnt <= 8'd0;
            end

            else if (w_w_handshake) begin
                w_beat_cnt <= w_beat_cnt + 1;
            end


            if (start_read && r_curr_state == R_IDLE) begin
                r_beat_cnt <= 8'd0;
            end

            else if (r_r_handshake) begin
                r_beat_cnt <= r_beat_cnt + 1;
            end
        end
    end
    //-----------------------counter-----------------------//

endmodule