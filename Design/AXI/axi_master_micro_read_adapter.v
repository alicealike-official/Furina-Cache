module axi_master_micro_read_adapter #(
    parameter AXI_DATA_WIDTH   = 32,   // AXI 数据位宽
    parameter AXI_ADDR_WIDTH   = 32,   // AXI 地址位宽
    parameter AXI_ID_WIDTH     = 4,    // AXI ID 位宽
    parameter AXI_BURST_LEN    = 16,   // 最大突发长度（一拍为单位）
    parameter MAX_OSD          = 4
) (
    //====================Transaction Region==================//
    //----------------Transaction control signal----------//
    input  wire                             start_read,     // 启动读突发（脉冲）
    input  wire [AXI_ADDR_WIDTH-1:0]        addr,           // 起始地址
    input  wire [7:0]                       burst_len,      // 突发长度
    input  wire [2:0]                       burst_size,     // 每拍字节数（2^size）
    input  wire [1:0]                       burst_type,     // 突发类型（通常 INCR）
    input  wire [AXI_ID_WIDTH-1:0]          id,             // 事务 ID
    output wire                             rd_req_ready,    // 可接受新读命令标志
    //----------------Transaction control signal----------//



    //----------------Transaction read signal----------//
    output wire [AXI_DATA_WIDTH-1:0]        rdata_o,        // 读数据逐拍输出
    output wire                             rdata_valid,    // 当前拍数据有效
    input  wire                             rdata_ready,    // 本拍已取走
    //----------------Transaction read signal----------//


    //----------------Transaction complete signal----------//
    output wire                             read_done,      // 读突发全部完成
    output wire [1:0]                       error_resp,     // 错误响应（暂简单化）
    //----------------Transaction complete signal----------//



    // ============================ AXI Interface ====================//
    //--------Clock and Reset-------//
    input  wire                             axi_aclk,
    input  wire                             axi_aresetn,
    //--------Clock and Reset-------//


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
   // ============================================================//
   //                                                             //
   //                           local param                       //
   //                                                             //
   // ============================================================//


    //-----------------------Fix AXI param-----------------------//
    localparam AXI_ARCACHE = 4'b0011;
    localparam AXI_ARPROT  = 3'b000;
    localparam AXI_ARLOCK  = 1'b0;
    localparam AXI_ARQOS   = 4'h0;
    localparam AXI_ARREGION= 4'h0;
    //-----------------------Fix AXI param-----------------------//

    //-----------------------FIFO param-----------------------//
    localparam CMD_FIFO_DEPTH  = MAX_OSD;  
    localparam CMD_FIFO_WIDTH = AXI_ID_WIDTH + AXI_ADDR_WIDTH + 8 + 3 + 2 + 1; // id+addr+len+size+burst+is_read
    localparam RDATA_FIFO_DEPTH = MAX_OSD * AXI_BURST_LEN; 
    //-----------------------FIFO param-----------------------//

    //-----------------------state param-----------------------//
    localparam AR_IDLE = 1'b0;
    localparam AR_SEND = 1'b1;
    //-----------------------state param-----------------------//


    // ============================================================//
    //                                                             //
    //                           wire define                       //
    //                                                             //
    // ============================================================//

    //-----------------------FIFO-----------------------//
    // 读请求 FIFO
    wire [CMD_FIFO_WIDTH-1:0]   cmd_fifo_din;
    wire [CMD_FIFO_WIDTH-1:0]   cmd_fifo_dout;
    wire                        cmd_fifo_push;
    wire                        cmd_fifo_pop;
    wire                        cmd_fifo_full;
    wire                        cmd_fifo_empty; 

    // 读数据 FIFO
    wire [AXI_DATA_WIDTH-1:0] rdata_fifo_din;
    wire                      rdata_fifo_wr_en;
    wire                      rdata_fifo_full;
    wire [AXI_DATA_WIDTH-1:0] rdata_fifo_dout;
    wire                      rdata_fifo_rd_en;
    wire                      rdata_fifo_empty;
    //-----------------------FIFO-----------------------//

    //-----------------------control signal-----------------------//
    wire                        m_axi_arhandshake;
    wire                        m_axi_rhandshake;
    wire                        rdata_handshake;


    wire                        ar_send_enable;
    wire                        read_done_condition;


    wire [MAX_OSD-1:0]          free_mask;
    wire [MAX_OSD-1:0]          rdata_match;
    wire                        entry_allocate;
    wire [MAX_OSD-1:0]          release_mask;
    wire                        entry_release;
    //-----------------------control signal-----------------------//


    //-----------------------指令解包-----------------------//
    wire [AXI_ID_WIDTH-1:0]    cmd_id;
    wire [AXI_ADDR_WIDTH-1:0]  cmd_addr;
    wire [7:0]                 cmd_len;
    wire [2:0]                 cmd_size;
    wire [1:0]                 cmd_burst;
    wire                       cmd_is_read;
    //-----------------------指令解包-----------------------//



    // ============================================================//
    //                                                             //
    //                           reg define                        //
    //                                                             //
    // ============================================================//


    //-----------------------state-----------------------//
    reg                         ar_cur_state;
    reg                         ar_next_state;
    //-----------------------state-----------------------//


    //-----------------------AR-----------------------//
    reg                         m_axi_arvalid_r;
    reg [AXI_ID_WIDTH-1:0]      m_axi_arid_r;
    reg [AXI_ADDR_WIDTH-1:0]    m_axi_araddr_r;
    reg [7:0]                   m_axi_arlen_r;
    reg [2:0]                   m_axi_arsize_r;
    reg [1:0]                   m_axi_arburst_r;
    //-----------------------AR-----------------------//


    //-----------------------事务状态表-----------------------//
    //用于标记记录在FIFO里面事务的状态，包括有效标志、ID、剩余长度和错误响应
    reg  [MAX_OSD-1:0]         entry_valid;
    reg  [AXI_ID_WIDTH-1:0]    entry_id [0:MAX_OSD-1];
    reg  [7:0]                 entry_len [0:MAX_OSD-1];
    reg  [1:0]                 entry_err [0:MAX_OSD-1];
    //-----------------------事务状态表-----------------------//

    //-----------------------trans-----------------------//
    reg [1:0]   error_resp_r;
    reg         read_done_r;
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
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .DEPTH(RDATA_FIFO_DEPTH)
    ) u_rdata_fifo(
        .clk(axi_aclk),
        .rst_n(axi_aresetn),
        .wr_data(rdata_fifo_din),
        .wr_en(rdata_fifo_push),
        .full(rdata_fifo_full),
        .rd_data(rdata_fifo_dout),
        .rd_en(rdata_fifo_pop),
        .empty(rdata_fifo_empty)
    );

    // ============================================================//
    //                                                             //
    //                         design function                     //
    //                                                             //
    // ============================================================//

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


    // ============================================================//
    //                                                             //
    //                       assign comb                           //
    //                                                             //
    // ============================================================//

    //-----------------------control signal-----------------------//
    assign m_axi_arhandshake    = m_axi_arvalid && m_axi_arready;
    assign m_axi_rhandshake     = m_axi_rvalid && m_axi_rready;
    assign rdata_handshake      = rdata_valid && rdata_ready;

    assign ar_send_enable       = !cmd_fifo_empty && (|(~entry_valid));

    assign free_mask            = find_free(entry_valid);
    assign entry_allocate       = cmd_fifo_pop;
    assign rdata_match          = find_by_id(m_axi_rid);
    assign read_done_condition  = m_axi_rhandshake && (|rdata_match) && m_axi_rlast;
    assign release_mask         = read_done_condition ? rdata_match : {MAX_OSD{1'b0}};
    assign entry_release        = (|release_mask);
    //-----------------------control signal-----------------------//


    //-----------------------cmd-FIFO-----------------------//
    assign cmd_fifo_push        = start_read && rd_req_ready;
    assign cmd_fifo_pop         = (ar_cur_state == AR_SEND) && m_axi_arhandshake;
    assign cmd_fifo_din = {id, addr, len, size, burst, 1'b1};
    assign {cmd_id, cmd_addr, cmd_len, cmd_size, cmd_burst, cmd_is_read} = cmd_fifo_dout;
    //-----------------------cmd-FIFO-----------------------//

    //-----------------------rdata-FIFO-----------------------//
    assign rdata_fifo_push  = m_axi_rvalid && !rdata_fifo_full;
    assign rdata_fifo_pop   = rdata_ready && !rdata_fifo_empty;
    assign rdata_fifo_din   = m_axi_rdata;
    assign rdata_o          = rdata_fifo_dout;
    //-----------------------rdata-FIFO-----------------------//



    // ============================================================//
    //                                                             //
    //                        always comb                          //
    //                                                             //
    // ============================================================//

    //-----------------------state-----------------------//
    always@(*) begin
        case(ar_cur_state) 
            AR_IDLE: begin
                if(ar_send_enable) begin
                    ar_next_state = AR_SEND;
                end

                else begin
                    ar_next_state = AR_IDLE;
                end
            end

            AR_SEND: begin
                if (m_axi_arhandshake) begin
                    ar_next_state = AR_IDLE;
                end

                else begin
                    ar_next_state = AR_SEND;
                end
            end

            default: begin
                ar_next_state = AR_IDLE;
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
            ar_cur_state <= AR_IDLE;
        end
        else begin
            ar_cur_state <= ar_next_state;
        end
    end
    //-----------------------state reg-----------------------//


    //-----------------------AR reg-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            m_axi_arvalid_r     <= 1'b0;
            m_axi_arid_r        <= {AXI_ID_WIDTH{1'b0}};
            m_axi_araddr_r      <= {AXI_ADDR_WIDTH_{1'b0}};
            m_axi_arlen_r       <= 8'b0;
            m_axi_arsize_r      <= 3'b0;
            m_axi_arburst_r     <= 2'b0;
        end

        else begin
            if (ar_cur_state == AR_IDLE && ar_send_enable) begin
                m_axi_arvalid_r     <= 1'b1;
                m_axi_arid_r        <= cmd_id;
                m_axi_araddr_r      <= cmd_addr;
                m_axi_arlen_r       <= cmd_len;
                m_axi_arsize_r      <= cmd_size;
                m_axi_arburst_r     <= cmd_burst;
            end

            if (ar_cur_state == AR_SEND && m_axi_arhandshake) begin
                m_axi_arvalid_r <= 1'b0;
            end
        end
    end
    //-----------------------AR reg-----------------------//


    //-----------------------trans_lot reg-----------------------//
    integer j;
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if(!axi_aresetn) begin
            entry_valid <= {MAX_OSD{1'b0}};
            for (j=0; j<MAX_OSD; j=j+1) begin
                entry_id[j]     <= {AXI_ID_WIDTH{1'b0}};
                entry_len[j]    <= 8'b0;
                entry_err[j]    <= 2'b0;
            end
        end

        else begin
            // allocate
            if(entry_allocate) begin
                entry_valid <= entry_valid | free_mask;
                for(j=0; j<MAX_OSD; j=j+1) begin
                    if(free_mask[j]) begin
                        entry_id[j]     <= m_axi_arid_r;
                        entry_len[j]    <= m_axi_arlen_r;
                        entry_err[j]    <= 2'b0;
                    end
                end
            end

            // refresh
            if (m_axi_rhandshake) begin
                for(j=0; j<MAX_OSD; j=j+1) begin
                    if(rdata_match[j] && entry_valid[j]) begin
                        entry_len[j]    <= entry_len[j]-1;
                        if (m_axi_rlast) begin
                            entry_err[j] <= m_axi_rresp;
                        end
                    end
                end
            end

            // release
            if (entry_release) begin
                entry_valid <= entry_valid & ~release_mask;
            end 


        end
    end
    //-----------------------trans_lot reg-----------------------//

    //-----------------------trans reg-----------------------//
    always@(posedge axi_aclk or negedge axi_aresetn) begin
        if (!axi_aresetn) begin
            read_done_r     <= 1'b0;
            error_resp_r    <= 2'b00;
        end
        
        else begin
            read_done_r <= read_done_condition;
            if(read_done_condition) begin
                for(j=0; j<MAX_OSD; j=j+1) begin
                    if(rdata_match[j]) begin
                        error_resp_r <= entry_err[j];
                    end
                end
            end
        end
    end
    //-----------------------trans reg-----------------------//

    // ============================================================//
    //                                                             //
    //                       assign output                         //
    //                                                             //
    // ============================================================//

    //-----------------------AR-----------------------//
    assign m_axi_arid       = m_axi_arid_r;
    assign m_axi_araddr     = m_axi_araddr_r;
    assign m_axi_arlen      = m_axi_arlen_r;
    assign m_axi_arsize     = m_axi_arsize_r;
    assign m_axi_arburst    = m_axi_arburst_r;
    assign m_axi_arlock     = AXI_ARLOCK;
    assign m_axi_arcache    = AXI_ARCACHE;
    assign m_axi_arprot     = AXI_ARPROT;
    assign m_axi_arqos      = AXI_ARQOS;
    assign m_axi_arregion   = AXI_ARREGION;
    assign m_axi_arvalid    = m_axi_arvalid_r;
    //-----------------------AR-----------------------//

    //-----------------------R-----------------------//
    assign m_axi_rready     = !rdata_fifo_empty;
    //-----------------------R-----------------------//

    //-----------------------Transaction-----------------------//
    assign rd_req_ready     = !cmd_fifo_full && (|(~entry_valid));
    assign read_done        = read_done_r;
    assign error_resp       = error_resp_r;
    //-----------------------Transaction-----------------------//
endmodule