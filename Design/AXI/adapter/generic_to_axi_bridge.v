// =============================================================================
//  generic_to_axi_bridge: 通用事务 → AXI4 协议桥
//  - 支持读写并发（读写通道独立 FSM）
//  - 事务侧: 脉冲式 start_read/start_write 启动, 逐拍流控 wdata/rdata
//  - AXI  侧: 标准 AXI4 Full 五通道主设备接口
// =============================================================================
module generic_to_axi_bridge #(
    parameter AXI_DATA_WIDTH   = 32,
    parameter AXI_ADDR_WIDTH   = 32,
    parameter AXI_ID_WIDTH     = 4
) (
    // ==================== Transaction Region ====================
    // 控制信号
    input  wire                             start_read,
    input  wire                             start_write,
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,
    input  wire [7:0]                       burst_len,      // 实际拍数 (1..256)
    input  wire [2:0]                       burst_size,     // 2^size 字节/拍
    input  wire [1:0]                       burst_type,     // FIXED/INCR/WRAP
    input  wire [AXI_ID_WIDTH-1:0]          id,

    // 写数据通道
    input  wire [AXI_DATA_WIDTH-1:0]        wdata_i,
    input  wire                             wdata_valid,
    output wire                             wdata_ready,

    // 读数据通道
    output wire [AXI_DATA_WIDTH-1:0]        rdata_o,
    output wire                             rdata_valid,
    input  wire                             rdata_ready,

    // 完成 / 错误
    output wire                             read_done,
    output wire                             write_done,
    output wire [1:0]                       error_resp,

    // ==================== AXI4 Master Interface ====================
    input  wire                             axi_aclk,
    input  wire                             axi_aresetn,

    // AW 通道
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

    // W 通道
    output wire [AXI_DATA_WIDTH-1:0]        m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0]    m_axi_wstrb,
    output wire                             m_axi_wlast,
    output wire                             m_axi_wvalid,
    input  wire                             m_axi_wready,

    // B 通道
    input  wire [AXI_ID_WIDTH-1:0]          m_axi_bid,
    input  wire [1:0]                       m_axi_bresp,
    input  wire                             m_axi_bvalid,
    output wire                             m_axi_bready,

    // AR 通道
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

    // R 通道
    input  wire [AXI_ID_WIDTH-1:0]          m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]        m_axi_rdata,
    input  wire [1:0]                       m_axi_rresp,
    input  wire                             m_axi_rlast,
    input  wire                             m_axi_rvalid,
    output wire                             m_axi_rready
);

    // ==============================
    //  AXI 固定配置 (事务侧未暴露)
    // ==============================
    localparam AXI_AWCACHE  = 4'b0011;  // normal non-cacheable bufferable
    localparam AXI_AWPROT   = 3'b000;   // unprivileged, secure, data
    localparam AXI_AWLOCK   = 1'b0;     // normal access
    localparam AXI_AWQOS    = 4'h0;
    localparam AXI_AWREGION = 4'h0;

    // ==============================
    //  写通道控制寄存器 / 锁存
    // ==============================
    reg [AXI_ADDR_WIDTH-1:0]    w_addr_r;
    reg [7:0]                   w_len_r;     // 实际拍数 (latched burst_len)
    reg [2:0]                   w_size_r;
    reg [1:0]                   w_type_r;
    reg [AXI_ID_WIDTH-1:0]      w_id_r;
    reg [7:0]                   w_beat_cnt;  // 当前已发送拍数 (0 .. len-1)

    reg [1:0]                   w_state;
    localparam W_IDLE   = 2'b00;
    localparam W_AW     = 2'b01;
    localparam W_DATA   = 2'b10;
    localparam W_BRESP  = 2'b11;

    // ==============================
    //  读通道控制寄存器 / 锁存
    // ==============================
    reg [AXI_ADDR_WIDTH-1:0]    r_addr_r;
    reg [7:0]                   r_len_r;     // 实际拍数
    reg [2:0]                   r_size_r;
    reg [1:0]                   r_type_r;
    reg [AXI_ID_WIDTH-1:0]      r_id_r;
    reg [7:0]                   r_beat_cnt;  // 当前已接收拍数 (0 .. len-1)

    reg [1:0]                   r_state;
    localparam R_IDLE   = 2'b00;
    localparam R_AR     = 2'b01;
    localparam R_DATA   = 2'b10;

    // ====================================================================
    //                          写通道 FSM
    // ====================================================================
    wire w_aw_handshake = (w_state == W_AW)     && m_axi_awvalid && m_axi_awready;
    wire w_w_handshake  = (w_state == W_DATA)   && m_axi_wvalid  && m_axi_wready;
    wire w_b_handshake  = (w_state == W_BRESP)  && m_axi_bvalid  && m_axi_bready;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            w_state     <= W_IDLE;
            w_addr_r    <= {AXI_ADDR_WIDTH{1'b0}};
            w_len_r     <= 8'd0;
            w_size_r    <= 3'd0;
            w_type_r    <= 2'b00;
            w_id_r      <= {AXI_ID_WIDTH{1'b0}};
            w_beat_cnt  <= 8'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (start_write) begin
                        w_addr_r    <= addr;
                        w_len_r     <= burst_len;
                        w_size_r    <= burst_size;
                        w_type_r    <= burst_type;
                        w_id_r      <= id;
                        w_beat_cnt  <= 8'd0;
                        w_state     <= W_AW;
                    end
                end

                W_AW: begin
                    if (w_aw_handshake)
                        w_state <= W_DATA;
                end

                W_DATA: begin
                    if (w_w_handshake) begin
                        if (w_beat_cnt == w_len_r - 1)
                            w_state <= W_BRESP;
                        else
                            w_beat_cnt <= w_beat_cnt + 1;
                    end
                end

                W_BRESP: begin
                    if (w_b_handshake)
                        w_state <= W_IDLE;
                end

                default: w_state <= W_IDLE;
            endcase
        end
    end

    // ------------------ 写通道 AXI 输出 ------------------
    assign m_axi_awid     = w_id_r;
    assign m_axi_awaddr   = w_addr_r;
    assign m_axi_awlen    = w_len_r - 8'd1;   // AXI: AWLEN = 实际拍数 - 1
    assign m_axi_awsize   = w_size_r;
    assign m_axi_awburst  = w_type_r;
    assign m_axi_awlock   = AXI_AWLOCK;
    assign m_axi_awcache  = AXI_AWCACHE;
    assign m_axi_awprot   = AXI_AWPROT;
    assign m_axi_awqos    = AXI_AWQOS;
    assign m_axi_awregion = AXI_AWREGION;
    assign m_axi_awvalid  = (w_state == W_AW);

    assign m_axi_wdata    = wdata_i;
    assign m_axi_wstrb    = {(AXI_DATA_WIDTH/8){1'b1}};  // 全字节使能
    assign m_axi_wlast    = (w_beat_cnt == w_len_r - 1);
    assign m_axi_wvalid   = (w_state == W_DATA) && wdata_valid;

    assign m_axi_bready   = (w_state == W_BRESP);

    // ------------------ 写通道事务侧输出 ------------------
    assign wdata_ready    = (w_state == W_DATA) && m_axi_wready;
    assign write_done     = w_b_handshake;
    // error_resp 由 B/R 通道共同驱动, 见末尾

    // ====================================================================
    //                          读通道 FSM
    // ====================================================================
    wire r_ar_handshake = (r_state == R_AR)   && m_axi_arvalid && m_axi_arready;
    wire r_r_handshake  = (r_state == R_DATA) && m_axi_rvalid  && m_axi_rready;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            r_state     <= R_IDLE;
            r_addr_r    <= {AXI_ADDR_WIDTH{1'b0}};
            r_len_r     <= 8'd0;
            r_size_r    <= 3'd0;
            r_type_r    <= 2'b00;
            r_id_r      <= {AXI_ID_WIDTH{1'b0}};
            r_beat_cnt  <= 8'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (start_read) begin
                        r_addr_r    <= addr;
                        r_len_r     <= burst_len;
                        r_size_r    <= burst_size;
                        r_type_r    <= burst_type;
                        r_id_r      <= id;
                        r_beat_cnt  <= 8'd0;
                        r_state     <= R_AR;
                    end
                end

                R_AR: begin
                    if (r_ar_handshake)
                        r_state <= R_DATA;
                end

                R_DATA: begin
                    if (r_r_handshake) begin
                        if (m_axi_rlast)
                            r_state <= R_IDLE;
                        else
                            r_beat_cnt <= r_beat_cnt + 1;
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

    // ------------------ 读通道 AXI 输出 ------------------
    assign m_axi_arid     = r_id_r;
    assign m_axi_araddr   = r_addr_r;
    assign m_axi_arlen    = r_len_r - 8'd1;   // AXI: ARLEN = 实际拍数 - 1
    assign m_axi_arsize   = r_size_r;
    assign m_axi_arburst  = r_type_r;
    assign m_axi_arlock   = AXI_AWLOCK;
    assign m_axi_arprot   = AXI_AWPROT;
    assign m_axi_arqos    = AXI_AWQOS;
    assign m_axi_arregion = AXI_AWREGION;
    assign m_axi_arcache  = AXI_AWCACHE;
    assign m_axi_arvalid  = (r_state == R_AR);

    assign m_axi_rready   = (r_state == R_DATA) && rdata_ready;

    // ------------------ 读通道事务侧输出 ------------------
    assign rdata_o     = m_axi_rdata;
    assign rdata_valid = (r_state == R_DATA) && m_axi_rvalid;
    assign read_done   = r_r_handshake && m_axi_rlast;

    // ====================================================================
    //  错误响应: 锁存最后一次 B/R 通道传输中的非 OKAY 响应
    // ====================================================================
    reg [1:0] err_r;
    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            err_r <= 2'b00;
        end else begin
            if (w_b_handshake && m_axi_bresp != 2'b00)
                err_r <= m_axi_bresp;
            if (r_r_handshake && m_axi_rresp != 2'b00)
                err_r <= m_axi_rresp;
        end
    end
    assign error_resp = err_r;

endmodule
