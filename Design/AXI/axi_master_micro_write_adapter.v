module axi_master_micro_write_adapter #(
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
    input  wire                             wr_req_valid,    // 启动写突发（脉冲）
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,           // 起始地址
    input  wire [7:0]                       burst_len,      // 突发长度
    input  wire [2:0]                       burst_size,     // 每拍字节数（2^size）
    input  wire [1:0]                       burst_type,     // 突发类型（通常 INCR）
    input  wire [AXI_ID_WIDTH-1:0]          id,             // 事务 ID
    output wire                             wr_req_ready,   // 可以发送下一个请求
    //----------------Transaction control signal----------//



    //----------------Transaction write signal----------//
    input  wire [(AXI_DATA_WIDTH/8)-1:0]    write_strb,     // 写掩码
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
    // ============================================================//
    //                                                             //
    //                      local paramter                         //
    //                                                             //
    // ============================================================//

    //-----------------------Fix AXI param-----------------------//
    localparam AXI_AWCACHE  = 4'b0011;
    localparam AXI_AWPROT   = 3'b000;
    localparam AXI_AWLOCK   = 1'b0;
    localparam AXI_AWQOS    = 4'h0;
    localparam AXI_AWREGION = 4'h0;
    //-----------------------Fix AXI param-----------------------//

    //-----------------------FIFO param-----------------------//
    localparam CMD_FIFO_DEPTH  = MAX_OSD;  
    //id+addr+len+size+burst+write_strb+is_write
    localparam CMD_FIFO_WIDTH = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2 + 1; 

    localparam W_LEN_FIFO_WIDTH = 8;
    localparam W_LEN_FIFO_DEPTH = MAX_OSD;

    localparam WDATA_FIFO_WIDTH = AXI_DATA_WIDTH + AXI_DATA_WIDTH/8;
    localparam WDATA_FIFO_DEPTH = MAX_OSD * AXI_BURST_LEN; 

    //-----------------------FIFO param-----------------------//

    //-----------------------state param-----------------------//
    localparam AW_IDLE  = 1'b0;
    localparam AW_TRANS = 1'b1;
    //-----------------------state param-----------------------//


    // ============================================================//
    //                                                             //
    //                         wire define                         //
    //                                                             //
    // ============================================================//

    //-----------------------cmd FIFO-----------------------//
    wire [CMD_FIFO_WIDTH-1:0]   cmd_fifo_din;
    wire [CMD_FIFO_WIDTH-1:0]   cmd_fifo_dout;
    wire                        cmd_fifo_push;
    wire                        cmd_fifo_pop;
    wire                        cmd_fifo_full;
    wire                        cmd_fifo_empty; 
    //-----------------------cmd FIFO-----------------------//

    //-----------------------w_len FIFO-----------------------//
    wire [7:0]                  w_len_fifo_din;
    wire [7:0]                  w_len_fifo_dout;
    wire                        w_len_fifo_push;
    wire                        w_len_fifo_pop;
    wire                        w_len_fifo_full;
    wire                        w_len_fifo_empty; 
    //-----------------------w_len FIFO-----------------------//

    //-----------------------data FIFO-----------------------//
    wire [AXI_DATA_WIDTH-1:0] wdata_fifo_din;
    wire                      wdata_fifo_push;
    wire                      wdata_fifo_full;
    wire [AXI_DATA_WIDTH-1:0] wdata_fifo_dout;
    wire                      wdata_fifo_pop;
    wire                      wdata_fifo_empty;
    //-----------------------data FIFO-----------------------//

    //-----------------------control signal-----------------------//
    wire    m_axi_awhandshake;
    wire    m_axi_whandshake;
    wire    m_axi_bhandshake;

    wire    wr_req_handshake;

    wire    aw_trans_enable;
    wire    aw_trans_reload;
    wire    aw_trans_done;
    //-----------------------control signal-----------------------//


    //-----------------------指令解包/打包-----------------------//
    wire [AXI_ID_WIDTH-1:0]         cmd_id;
    wire [AXI_ADDR_WIDTH-1:0]       cmd_addr;
    wire [7:0]                      cmd_burst_len;
    wire [2:0]                      cmd_burst_size;
    wire [1:0]                      cmd_burst_type;
    wire                            cmd_is_write;

    wire [AXI_DATA_WIDTH-1:0]       wdata_fifo_out;
    wire [(AXI_DATA_WIDTH/8)-1:0]   write_strb_fifo_out;
    //-----------------------指令解包/打包-----------------------//



    // ============================================================//
    //                                                             //
    //                         reg define                          //
    //                                                             //
    // ============================================================//

    
    //-----------------------state-----------------------//
    reg                      aw_cur_state;
    reg                      aw_next_state;
    //-----------------------state-----------------------//


    //-----------------------AW-----------------------//
    reg [AXI_ID_WIDTH-1:0]          m_axi_awid_r;
    reg [AXI_ADDR_WIDTH-1:0]        m_axi_awaddr_r;
    reg [7:0]                       m_axi_awlen_r;
    reg [2:0]                       m_axi_awsize_r;
    reg [1:0]                       m_axi_awburst_r;
    // reg                             m_axi_awlock_r;
    // reg [3:0]                       m_axi_awcache_r;
    // reg [2:0]                       m_axi_awprot_r;
    // reg [3:0]                       m_axi_awqos_r;
    // reg [3:0]                       m_axi_awregion_r;
    reg                             m_axi_awvalid_r;
    //-----------------------AW-----------------------//


    //-----------------------W-----------------------//
    reg [AXI_DATA_WIDTH-1:0]        m_axi_wdata_r;
    reg [(AXI_DATA_WIDTH/8)-1:0]    m_axi_wstrb_r;
    reg                             m_axi_wlast_r;
    reg                             m_axi_wvalid_r;
    //-----------------------W-----------------------//


    //-----------------------count-----------------------//
    reg                             w_active;
    reg [7:0]                       w_burst_count;
    reg [7:0]                       wr_outstanding_count;
    //-----------------------count-----------------------//


    //-----------------------trans-----------------------//
    reg                             write_done_r;
    reg [1:0]                       error_resp_r;
    //-----------------------trans-----------------------//


    // ============================================================//
    //                                                             //
    //                           FIFO INST                         //
    //                                                             //
    // ============================================================//

    sync_fifo #(
        .DATA_WIDTH(CMD_FIFO_WIDTH),
        .DEPTH(CMD_FIFO_DEPTH)
    ) u_cmd_fifo(
        .clk(axi_aclk),
        .rst_n(axi_aresetn),
        .wr_data(cmd_fifo_din),
        .wr_en(cmd_fifo_push),
        .full(cmd_fifo_full),
        .rd_data(cmd_fifo_dout),
        .rd_en(cmd_fifo_pop),
        .empty(cmd_fifo_empty)
    );

    sync_fifo #(
        .DATA_WIDTH(W_LEN_FIFO_WIDTH),
        .DEPTH(W_LEN_FIFO_DEPTH)
    ) u_w_len_fifo(
        .clk(axi_aclk),
        .rst_n(axi_aresetn),
        .wr_data(w_len_fifo_din),
        .wr_en(w_len_fifo_push),
        .full(w_len_fifo_full),
        .rd_data(w_len_fifo_dout),
        .rd_en(w_len_fifo_pop),
        .empty(w_len_fifo_empty)
    );

    sync_fifo #(
        .DATA_WIDTH(WDATA_FIFO_WIDTH),
        .DEPTH(WDATA_FIFO_DEPTH)
    ) u_wdata_fifo(
        .clk(axi_aclk),
        .rst_n(axi_aresetn),
        .wr_data(wdata_fifo_din),
        .wr_en(wdata_fifo_push),
        .full(wdata_fifo_full),
        .rd_data(wdata_fifo_dout),
        .rd_en(wdata_fifo_pop),
        .empty(wdata_fifo_empty)
    );

    // ============================================================//
    //                                                             //
    //                         assign comb                         //
    //                                                             //
    // ============================================================//

    //-----------------------control signal-----------------------//
    assign m_axi_awhandshake    = m_axi_awvalid && m_axi_awready;
    assign m_axi_whandshake     = m_axi_wvalid && m_axi_wready;
    assign m_axi_bhandshake     = m_axi_bvalid && m_axi_bready;

    assign wr_req_handshake     = wr_req_valid && wr_req_ready;
    assign wdata_handshake      = wdata_valid && wdata_ready;

    assign aw_trans_enable      = (aw_cur_state == AW_IDLE) && !cmd_fifo_empty;
    assign aw_trans_reload      = (aw_cur_state == AW_TRANS) && m_axi_awhandshake 
                                    && !cmd_fifo_empty && !w_len_fifo_full;
    assign aw_trans_done        = (aw_cur_state == AW_TRANS) && m_axi_awhandshake && cmd_fifo_empty; 

    //-----------------------control signal-----------------------//

    //-----------------------cmd FIFO-----------------------//
    assign cmd_fifo_din         = {id, addr, burst_len, burst_size, burst_type, 1'b1};
    assign {cmd_id, cmd_addr, cmd_burst_len, cmd_burst_size, cmd_burst_type, cmd_is_write} = cmd_fifo_dout;

    // assign cmd_fifo_push        = (!cmd_fifo_full && wr_req_valid);
    assign cmd_fifo_push        = wr_req_handshake;
    assign cmd_fifo_pop         = aw_trans_enable || aw_trans_reload;
    //-----------------------cmd FIFO-----------------------//


    //-----------------------w_len FIFO-----------------------//
    assign w_len_fifo_din       = m_axi_awlen_r;

    assign w_len_fifo_push      = m_axi_awhandshake;
    assign w_len_fifo_pop       = !w_active && !w_len_fifo_empty;
    //-----------------------w_len FIFO-----------------------//

    //-----------------------wdata FIFO-----------------------//
    assign wdata_fifo_din       = {wdata_i, write_strb};
    assign {wdata_fifo_out, write_strb_fifo_out} = wdata_fifo_dout;
    assign wdata_fifo_push      = wdata_handshake;
    assign wdata_fifo_pop       = m_axi_whandshake;
    //-----------------------wdata FIFO-----------------------//


    // ============================================================//
    //                                                             //
    //                         always comb                         //
    //                                                             //
    // ============================================================//

    //-----------------------state-----------------------//
    always@(*) begin
        case(aw_cur_state)
            AW_IDLE: begin
                aw_next_state = aw_trans_enable ? AW_TRANS : AW_IDLE;
            end

            AW_TRANS: begin
                aw_next_state = aw_trans_done ? AW_IDLE : AW_TRANS;
            end

            default: begin
                aw_next_state = AW_IDLE;
            end
        endcase
    end
    //-----------------------state-----------------------//


    // ============================================================//
    //                                                             //
    //                         reg control                         //
    //                                                             //
    // ============================================================//

    //-----------------------state reg-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            aw_cur_state <= 1'b0;
        end

        else begin
            aw_cur_state <= aw_next_state;
        end
    end
    //-----------------------state reg-----------------------//


    //-----------------------AW reg-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            m_axi_awid_r    <= {AXI_ID_WIDTH{1'b0}};
            m_axi_awaddr_r  <= {AXI_ADDR_WIDTH{1'b0}};
            m_axi_awlen_r   <= 8'b0;
            m_axi_awsize_r  <= 3'b0;
            m_axi_awburst_r <= 2'b0;
            m_axi_awvalid_r <= 0;
        end

        else begin
            if (cmd_fifo_pop) begin
                m_axi_awid_r    <= cmd_id;
                m_axi_awaddr_r  <= cmd_addr;
                m_axi_awlen_r   <= cmd_burst_len;
                m_axi_awsize_r  <= cmd_burst_size;
                m_axi_awburst_r <= cmd_burst_type;
                m_axi_awvalid_r <= 1'b1;
            end

            if (aw_trans_done) begin
                m_axi_awvalid_r <= 1'b0;
            end
        end
    end
    //-----------------------AW reg-----------------------//


    //-----------------------W reg-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            m_axi_wdata_r   <= {AXI_DATA_WIDTH{1'b0}};
            m_axi_wstrb_r   <= {(AXI_DATA_WIDTH/8){1'b0}};
            m_axi_wlast_r   <= 1'b0;
            m_axi_wvalid_r  <= 1'b0;
        end

        else begin
            m_axi_wvalid_r  <= w_active && !wdata_fifo_empty;

            // if (m_axi_whandshake) begin
            //     m_axi_wdata_r   <= wdata_i;
            //     m_axi_wstrb_r   <= write_strb;
            // end

            // if (w_active && w_burst_count == 0) begin
            //     m_axi_wlast_r <= 1'b1;
            // end

            // else begin
            //     m_axi_wlast_r <= 1'b0;
            // end

            if (w_active && !wdata_fifo_empty) begin
                m_axi_wdata_r   <= wdata_fifo_out;
                m_axi_wstrb_r   <= write_strb_fifo_out;
                m_axi_wlast_r   <= (w_burst_count == 0);
                m_axi_wvalid_r  <= 1'b1;
            end

            else if (m_axi_whandshake) begin
                m_axi_wvalid_r  <= 1'b0;
            end
        end
    end
    //-----------------------W reg-----------------------//


    //-----------------------outstanding count-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            wr_outstanding_count <= 8'b0;
        end

        else begin
            if (m_axi_awhandshake && !m_axi_bhandshake) begin
                wr_outstanding_count <= wr_outstanding_count+1;
            end

            if (!m_axi_awhandshake && m_axi_bhandshake) begin
                wr_outstanding_count <= wr_outstanding_count-1;
            end

            if (m_axi_awhandshake && m_axi_bhandshake) begin
                wr_outstanding_count <= wr_outstanding_count;
            end
        end
    end
    //-----------------------outstanding count-----------------------//

    //-----------------------burst count-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            w_burst_count   <= 8'b0;
            w_active        <= 1'b0;
        end

        else begin
            if (!w_active && !w_len_fifo_empty) begin
                w_burst_count   <= w_len_fifo_dout;
                w_active        <= 1'b1;
            end

            else if(w_active && m_axi_whandshake) begin
                if (w_burst_count == 0) begin
                    w_active <= 1'b0;
                end

                else begin
                    w_burst_count <= w_burst_count-1;
                end
            end
        end
    end
    //-----------------------burst count-----------------------//


    //-----------------------trans reg-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            write_done_r    <= 1'b0;
            error_resp_r    <= 2'b0;
        end

        else begin
            write_done_r    <= m_axi_bhandshake;
            if (m_axi_bhandshake) begin
                error_resp_r <= m_axi_bresp;
            end
        end
    end
    //-----------------------trans reg-----------------------//


    // ============================================================//
    //                                                             //
    //                       assign output                         //
    //                                                             //
    // ============================================================//

    //-----------------------AW-----------------------//
    assign m_axi_awid     = m_axi_awid_r;
    assign m_axi_awaddr   = m_axi_awaddr_r;
    assign m_axi_awlen    = m_axi_awlen_r;
    assign m_axi_awsize   = m_axi_awsize_r;
    assign m_axi_awburst  = m_axi_awburst_r;
    assign m_axi_awlock   = AXI_AWLOCK;
    assign m_axi_awcache  = AXI_AWCACHE;
    assign m_axi_awprot   = AXI_AWPROT;
    assign m_axi_awqos    = AXI_AWQOS;
    assign m_axi_awregion = AXI_AWREGION;
    assign m_axi_awvalid  = m_axi_awvalid_r;
    //-----------------------AW-----------------------//


    //-----------------------W-----------------------//
    assign m_axi_wdata  = m_axi_wdata_r;
    assign m_axi_wstrb  = m_axi_wstrb_r;
    assign m_axi_wlast  = m_axi_wlast_r;
    assign m_axi_wvalid = m_axi_wvalid_r;
    //-----------------------W-----------------------//

    //-----------------------B-----------------------//
    assign m_axi_bready = 1'b1;
    //-----------------------B-----------------------//


    //-----------------------trans-----------------------//
    assign wr_req_ready = !cmd_fifo_full && (wr_outstanding_count < MAX_OSD);;
    assign wdata_ready  = !wdata_fifo_full;
    assign write_done   = write_done_r;
    assign error_resp   = error_resp_r;
    //-----------------------trans-----------------------//
endmodule