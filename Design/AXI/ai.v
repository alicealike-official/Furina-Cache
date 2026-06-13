// ============================================================================
// 写适配器：将上游的写事务请求转换为 AXI 写通道操作，支持多事务 Outstanding。
// 特性：
//  - 输入 start_write 脉冲，接收 wdata 流，输出 write_done 脉冲。
//  - 命令 FIFO 暂存写请求，AW 通道可流水发送地址。
//  - 写数据 FIFO 缓存上游数据，W 通道按拍发送并自动产生 WLAST。
//  - 事务状态表跟踪每个未完成写事务的 ID、剩余拍数、写选通等。
//  - B 通道响应按 BID 匹配，完成事务并输出 write_done。
// ============================================================================
module axi_master_wr_adapter #(
    parameter AXI_DATA_WIDTH   = 32,
    parameter AXI_ADDR_WIDTH   = 32,
    parameter AXI_ID_WIDTH     = 4,
    parameter AXI_BURST_LEN    = 16,
    parameter MAX_OSD          = 4
) (
    // ======================== 事务接口 ========================
    input  wire                             start_write,     // 写请求脉冲
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,
    input  wire [7:0]                       burst_len,
    input  wire [2:0]                       burst_size,
    input  wire [1:0]                       burst_type,
    input  wire [(AXI_DATA_WIDTH/8)-1:0]    write_strb,      // 写字节使能
    input  wire [AXI_ID_WIDTH-1:0]          id,
    output wire                             wr_req_ready,    // 可接受新写命令

    input  wire [AXI_DATA_WIDTH-1:0]        wdata_i,
    input  wire                             wdata_valid,
    output wire                             wdata_ready,     // 上游可以发送写数据
    output wire                             write_done,      // 写事务完成脉冲
    output wire [1:0]                       error_resp,

    // ======================== AXI 写通道 ========================
    input  wire                             axi_aclk,
    input  wire                             axi_aresetn,
    // AW
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
    // W
    output wire [AXI_DATA_WIDTH-1:0]        m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0]    m_axi_wstrb,
    output wire                             m_axi_wlast,
    output wire                             m_axi_wvalid,
    input  wire                             m_axi_wready,
    // B
    input  wire [AXI_ID_WIDTH-1:0]          m_axi_bid,
    input  wire [1:0]                       m_axi_bresp,
    input  wire                             m_axi_bvalid,
    output wire                             m_axi_bready
);

    // ======================== 固定 AXI 属性 ========================
    localparam AXI_AWCACHE  = 4'b0011;
    localparam AXI_AWPROT   = 3'b000;
    localparam AXI_AWLOCK   = 1'b0;
    localparam AXI_AWQOS    = 4'h0;
    localparam AXI_AWREGION = 4'h0;

    // ======================== FIFO 深度 ========================
    localparam CMD_FIFO_DEPTH   = MAX_OSD;
    localparam WDATA_FIFO_DEPTH = MAX_OSD * AXI_BURST_LEN;

    // ======================== 命令 FIFO（写命令） ========================
    localparam CMD_FIFO_WIDTH = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2 + (AXI_DATA_WIDTH/8) + 1;
    wire [CMD_FIFO_WIDTH-1:0] cmd_fifo_din, cmd_fifo_dout;
    wire                      cmd_fifo_push, cmd_fifo_pop;
    wire                      cmd_fifo_full, cmd_fifo_empty;

    assign cmd_fifo_push = start_write && wr_req_ready;
    assign cmd_fifo_din  = {id, addr, burst_len, burst_size, burst_type, write_strb, 1'b0}; // 最后 1'b0 表示写事务

    sync_fifo #(
        .DATA_WIDTH(CMD_FIFO_WIDTH),
        .DEPTH(CMD_FIFO_DEPTH)
    ) cmd_fifo (
        .clk      (axi_aclk),
        .rst_n    (axi_aresetn),
        .wr_data  (cmd_fifo_din),
        .wr_en    (cmd_fifo_push),
        .full     (cmd_fifo_full),
        .rd_data  (cmd_fifo_dout),
        .rd_en    (cmd_fifo_pop),
        .empty    (cmd_fifo_empty)
    );

    wire [AXI_ID_WIDTH-1:0]    cmd_id;
    wire [AXI_ADDR_WIDTH-1:0]  cmd_addr;
    wire [7:0]                 cmd_len;
    wire [2:0]                 cmd_size;
    wire [1:0]                 cmd_burst;
    wire [(AXI_DATA_WIDTH/8)-1:0] cmd_strb;
    wire                       cmd_is_read;
    assign {cmd_id, cmd_addr, cmd_len, cmd_size, cmd_burst, cmd_strb, cmd_is_read} = cmd_fifo_dout;

    // ======================== 写数据 FIFO ========================
    localparam WDATA_FIFO_WIDTH = AXI_DATA_WIDTH + (AXI_DATA_WIDTH/8);
    wire [WDATA_FIFO_WIDTH-1:0] wdata_fifo_din, wdata_fifo_dout;
    wire                        wdata_fifo_push, wdata_fifo_pop;
    wire                        wdata_fifo_full, wdata_fifo_empty;

    assign wdata_fifo_push = wdata_valid && wdata_ready;
    assign wdata_fifo_din  = {wdata_i, write_strb};   // 打包数据与 strobe

    sync_fifo #(
        .DATA_WIDTH(WDATA_FIFO_WIDTH),
        .DEPTH(WDATA_FIFO_DEPTH)
    ) wdata_fifo (
        .clk      (axi_aclk),
        .rst_n    (axi_aresetn),
        .wr_data  (wdata_fifo_din),
        .wr_en    (wdata_fifo_push),
        .full     (wdata_fifo_full),
        .rd_data  (wdata_fifo_dout),
        .rd_en    (wdata_fifo_pop),
        .empty    (wdata_fifo_empty)
    );

    wire [AXI_DATA_WIDTH-1:0]     wdata_fifo_data;
    wire [(AXI_DATA_WIDTH/8)-1:0] wdata_fifo_strb;
    assign {wdata_fifo_data, wdata_fifo_strb} = wdata_fifo_dout;

    // ======================== 事务状态表 ========================
    reg  [MAX_OSD-1:0]         entry_valid;
    reg  [AXI_ID_WIDTH-1:0]    entry_id [0:MAX_OSD-1];
    reg  [7:0]                 entry_len [0:MAX_OSD-1];   // 剩余拍数
    reg  [1:0]                 entry_err [0:MAX_OSD-1];
    // 注意：写事务在数据阶段需要 strobe，但 strobe 已随数据存入 FIFO，无需表内存储。

    function [MAX_OSD-1:0] find_free;
        input [MAX_OSD-1:0] valid;
        integer i;
        begin
            find_free = 0;
            for (i=0; i<MAX_OSD; i=i+1) begin
                if (!valid[i]) begin
                    find_free[i] = 1'b1;
                    break;
                end
            end
        end
    endfunction

    function [MAX_OSD-1:0] find_by_id;
        input [AXI_ID_WIDTH-1:0] id_in;
        integer i;
        begin
            find_by_id = 0;
            for (i=0; i<MAX_OSD; i=i+1) begin
                if (entry_valid[i] && (entry_id[i] == id_in))
                    find_by_id[i] = 1'b1;
            end
        end
    endfunction

    // ======================== AW 通道发送逻辑 ========================
    reg                       aw_valid_r;
    reg [AXI_ID_WIDTH-1:0]    aw_id_r;
    reg [AXI_ADDR_WIDTH-1:0]  aw_addr_r;
    reg [7:0]                 aw_len_r;
    reg [2:0]                 aw_size_r;
    reg [1:0]                 aw_burst_r;

    localparam AW_IDLE = 1'b0, AW_SEND = 1'b1;
    reg aw_state;
    wire aw_handshake = m_axi_awvalid && m_axi_awready;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            aw_state   <= AW_IDLE;
            aw_valid_r <= 1'b0;
        end else begin
            case (aw_state)
                AW_IDLE: begin
                    if (!cmd_fifo_empty && (|(~entry_valid))) begin
                        aw_id_r    <= cmd_id;
                        aw_addr_r  <= cmd_addr;
                        aw_len_r   <= cmd_len;
                        aw_size_r  <= cmd_size;
                        aw_burst_r <= cmd_burst;
                        aw_valid_r <= 1'b1;
                        aw_state   <= AW_SEND;
                    end
                end
                AW_SEND: begin
                    if (aw_handshake) begin
                        aw_valid_r <= 1'b0;
                        aw_state   <= AW_IDLE;
                    end
                end
            endcase
        end
    end

    assign cmd_fifo_pop = (aw_state == AW_SEND) && aw_handshake;

    assign m_axi_awid    = aw_id_r;
    assign m_axi_awaddr  = aw_addr_r;
    assign m_axi_awlen   = aw_len_r;
    assign m_axi_awsize  = aw_size_r;
    assign m_axi_awburst = aw_burst_r;
    assign m_axi_awlock  = AXI_AWLOCK;
    assign m_axi_awcache = AXI_AWCACHE;
    assign m_axi_awprot  = AXI_AWPROT;
    assign m_axi_awqos   = AXI_AWQOS;
    assign m_axi_awregion= AXI_AWREGION;
    assign m_axi_awvalid = aw_valid_r;

    // ======================== 事务表分配（AW 握手时） ========================
    wire [MAX_OSD-1:0] free_mask_wr = find_free(entry_valid);
    wire               allocate_wr  = (aw_state == AW_SEND) && aw_handshake;
    reg  [MAX_OSD-1:0] alloc_onehot_wr;

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            entry_valid <= 0;
        end else begin
            if (allocate_wr) begin
                alloc_onehot_wr <= free_mask_wr;
                entry_valid     <= entry_valid | free_mask_wr;
            end
            if (|release_mask_wr)
                entry_valid     <= entry_valid & ~release_mask_wr;
        end
    end

    integer j;
    always @(posedge axi_aclk) begin
        if (allocate_wr) begin
            for (j=0; j<MAX_OSD; j=j+1) begin
                if (free_mask_wr[j]) begin
                    entry_id[j]  <= aw_id_r;
                    entry_len[j] <= aw_len_r;    // 初始总拍数
                    entry_err[j] <= 2'b00;
                end
            end
        end
    end

    // ======================== W 通道发送逻辑 ========================
    // 需要一个状态机选择当前活跃的写事务，并持续发送数据直到剩余拍数为零
    reg  [MAX_OSD-1:0] w_active_entry;
    reg                w_active;
    reg  [7:0]         w_beat_remain;   // 当前活跃事务的剩余拍数

    // 查找下一个有数据要发送的写事务（有效、剩余拍数 > 0）
    function [MAX_OSD-1:0] find_w_entry;
        integer i;
        begin
            find_w_entry = 0;
            for (i=0; i<MAX_OSD; i=i+1) begin
                if (entry_valid[i] && (entry_len[i] > 0)) begin
                    find_w_entry[i] = 1'b1;
                    break;
                end
            end
        end
    endfunction

    wire [MAX_OSD-1:0] next_w_entry = find_w_entry();

    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            w_active       <= 1'b0;
            w_active_entry <= 0;
            w_beat_remain  <= 8'd0;
        end else begin
            if (!w_active) begin
                // 启动新的写事务
                if (|next_w_entry) begin
                    w_active       <= 1'b1;
                    w_active_entry <= next_w_entry;
                    // 从表加载剩余拍数（组合逻辑配合）
                end
            end else begin
                if (m_axi_wvalid && m_axi_wready) begin
                    if (w_beat_remain == 1) begin
                        w_active <= 1'b0;   // 数据阶段结束
                    end else begin
                        w_beat_remain <= w_beat_remain - 1;
                    end
                end
            end
        end
    end

    // 加载剩余拍数（避免延迟一拍）
    reg [7:0] w_remain_load;
    integer m;
    always @(*) begin
        w_remain_load = 8'd0;
        for (m=0; m<MAX_OSD; m=m+1) begin
            if (w_active && w_active_entry[m])
                w_remain_load = entry_len[m];
        end
    end

    // W 通道有效条件：有活跃写事务且写数据 FIFO 非空
    assign wdata_fifo_pop = m_axi_wvalid && m_axi_wready;
    assign m_axi_wvalid   = w_active && !wdata_fifo_empty;
    assign m_axi_wdata    = wdata_fifo_data;
    assign m_axi_wstrb    = wdata_fifo_strb;
    assign m_axi_wlast    = (w_beat_remain == 1);

    // 更新事务表中活跃写事务的剩余拍数
    always @(posedge axi_aclk) begin
        if (wdata_fifo_pop) begin
            for (m=0; m<MAX_OSD; m=m+1) begin
                if (w_active && w_active_entry[m]) begin
                    entry_len[m] <= entry_len[m] - 1;
                end
            end
        end
    end

    // ======================== 写数据流控 ========================
    // 上游 wdata_ready 取决于写数据 FIFO 是否未满
    assign wdata_ready = !wdata_fifo_full;

    // ======================== B 通道响应处理 ========================
    assign m_axi_bready = 1'b1;  // 始终可接收

    wire b_handshake = m_axi_bvalid && m_axi_bready;
    wire [MAX_OSD-1:0] b_match = find_by_id(m_axi_bid);

    // 写完成脉冲
    reg write_done_r;
    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn)
            write_done_r <= 1'b0;
        else
            write_done_r <= b_handshake;
    end
    assign write_done = write_done_r;

    // 释放已完成事务
    wire [MAX_OSD-1:0] release_mask_wr = b_handshake ? b_match : 0;

    // 更新错误信息
    always @(posedge axi_aclk) begin
        if (b_handshake) begin
            for (m=0; m<MAX_OSD; m=m+1) begin
                if (b_match[m])
                    entry_err[m] <= m_axi_bresp;
            end
        end
    end

    // ======================== 错误输出 ========================
    reg [1:0] last_error;
    always @(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn)
            last_error <= 2'b00;
        else if (b_handshake) begin
            for (m=0; m<MAX_OSD; m=m+1) begin
                if (b_match[m])
                    last_error <= m_axi_bresp;
            end
        end
    end
    assign error_resp = last_error;

    // ======================== 就绪信号 ========================
    assign wr_req_ready = (|(~entry_valid)) && !cmd_fifo_full;

endmodule