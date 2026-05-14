// =============================================================================
//  tb_axi_master_micro_adapter: 定向测试
//  验证: 单次写 / 单次读 / 读写并发
// =============================================================================
`timescale 1ns / 1ps

module tb_axi_master_micro_adapter;

    // ==============================
    //  参数
    // ==============================
    localparam CLK_PERIOD = 10;
    localparam D_WIDTH = 32;
    localparam A_WIDTH = 32;
    localparam ID_WIDTH = 4;

    // ==============================
    //  DUT 信号
    // ==============================
    logic                       clk;
    logic                       rst_n;

    // ------ 事务侧 ------
    logic                       start_read;
    logic                       start_write;
    logic [A_WIDTH-1:0]         addr;
    logic [7:0]                 burst_len;
    logic [2:0]                 burst_size;
    logic [1:0]                 burst_type;
    logic [(D_WIDTH/8)-1:0]     write_strb;
    logic [ID_WIDTH-1:0]        id;

    logic [D_WIDTH-1:0]         wdata_i;
    logic                       wdata_valid;
    logic                       wdata_ready;

    logic [D_WIDTH-1:0]         rdata_o;
    logic                       rdata_valid;
    logic                       rdata_ready;

    logic                       read_done;
    logic                       write_done;
    logic [1:0]                 error_resp;

    // ------ AXI Master ------
    logic [ID_WIDTH-1:0]        m_axi_awid;
    logic [A_WIDTH-1:0]         m_axi_awaddr;
    logic [7:0]                 m_axi_awlen;
    logic [2:0]                 m_axi_awsize;
    logic [1:0]                 m_axi_awburst;
    logic                       m_axi_awlock;
    logic [3:0]                 m_axi_awcache;
    logic [2:0]                 m_axi_awprot;
    logic [3:0]                 m_axi_awqos;
    logic [3:0]                 m_axi_awregion;
    logic                       m_axi_awvalid;
    logic                       m_axi_awready;

    logic [D_WIDTH-1:0]         m_axi_wdata;
    logic [(D_WIDTH/8)-1:0]     m_axi_wstrb;
    logic                       m_axi_wlast;
    logic                       m_axi_wvalid;
    logic                       m_axi_wready;

    logic [ID_WIDTH-1:0]        m_axi_bid;
    logic [1:0]                 m_axi_bresp;
    logic                       m_axi_bvalid;
    logic                       m_axi_bready;

    logic [ID_WIDTH-1:0]        m_axi_arid;
    logic [A_WIDTH-1:0]         m_axi_araddr;
    logic [7:0]                 m_axi_arlen;
    logic [2:0]                 m_axi_arsize;
    logic [1:0]                 m_axi_arburst;
    logic                       m_axi_arlock;
    logic [3:0]                 m_axi_arcache;
    logic [2:0]                 m_axi_arprot;
    logic [3:0]                 m_axi_arqos;
    logic [3:0]                 m_axi_arregion;
    logic                       m_axi_arvalid;
    logic                       m_axi_arready;

    logic [ID_WIDTH-1:0]        m_axi_rid;
    logic [D_WIDTH-1:0]         m_axi_rdata;
    logic [1:0]                 m_axi_rresp;
    logic                       m_axi_rlast;
    logic                       m_axi_rvalid;
    logic                       m_axi_rready;

    // ==============================
    //  DUT 实例化
    // ==============================
    axi_master_micro_adapter #(
        .AXI_DATA_WIDTH(D_WIDTH),
        .AXI_ADDR_WIDTH(A_WIDTH),
        .AXI_ID_WIDTH(ID_WIDTH),
        .AXI_BURST_LEN(16)
    ) u_dut (
        // 事务侧
        .start_read     (start_read),
        .start_write    (start_write),
        .addr           (addr),
        .burst_len      (burst_len),
        .burst_size     (burst_size),
        .burst_type     (burst_type),
        .write_strb     (write_strb),
        .id             (id),
        .wdata_i        (wdata_i),
        .wdata_valid    (wdata_valid),
        .wdata_ready    (wdata_ready),
        .rdata_o        (rdata_o),
        .rdata_valid    (rdata_valid),
        .rdata_ready    (rdata_ready),
        .read_done      (read_done),
        .write_done     (write_done),
        .error_resp     (error_resp),

        // AXI
        .axi_aclk       (clk),
        .axi_aresetn    (rst_n),

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
        .m_axi_bready   (m_axi_bready),

        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arqos    (m_axi_arqos),
        .m_axi_arregion (m_axi_arregion),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),

        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // ==============================
    //  时钟 / 复位
    // ==============================
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        clk   = 0;
        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
    end

    // ==============================
    //  事务侧默认值
    // ==============================
    initial begin
        start_read  = 0;
        start_write = 0;
        addr        = 0;
        burst_len   = 0;
        burst_size  = 3'b010;       // 4 bytes / beat
        burst_type  = 2'b01;        // INCR
        write_strb  = '1;
        id          = 0;
        wdata_i     = 0;
        wdata_valid = 0;
        rdata_ready = 0;
    end

    // ==============================
    //  AXI Slave 模型默认值
    // ==============================
    initial begin
        m_axi_awready = 1;  // always ready
        m_axi_wready  = 1;  // always ready
        m_axi_bid     = 0;
        m_axi_bresp   = 0;
        m_axi_bvalid  = 0;
        m_axi_arready = 1;
        m_axi_rid     = 0;
        m_axi_rdata   = 0;
        m_axi_rresp   = 0;
        m_axi_rlast   = 0;
        m_axi_rvalid  = 0;
    end

    // ==============================
    //  Slave 任务：处理写事务
    // ==============================
    task automatic slave_handle_write;
        input int exp_len;     // AWLEN (AXI convention)
        input string name;
        logic [7:0] len;
        int i;

        // 等待 AW 握手
        @(posedge clk);
        while (!(m_axi_awvalid && m_axi_awready))
            @(posedge clk);
        len = m_axi_awlen;
        $display("[%0t] %s AW: addr=0x%08h len=%0d", $time, name, m_axi_awaddr, len);

        // 接收 W 数据
        for (i = 0; i <= len; i++) begin
            @(posedge clk);
            while (!(m_axi_wvalid && m_axi_wready))
                @(posedge clk);
            $display("[%0t] %s W[%0d]: data=0x%08h last=%b", $time, name, i, m_axi_wdata, m_axi_wlast);
        end

        // 返回 B 响应 (延迟 1 拍)
        repeat(2) @(posedge clk);
        m_axi_bvalid <= 1;
        m_axi_bid    <= m_axi_awid;
        m_axi_bresp  <= 2'b00;  // OKAY
        @(posedge clk);
        while (!(m_axi_bvalid && m_axi_bready))
            @(posedge clk);
        $display("[%0t] %s B: id=%0d resp=%b", $time, name, m_axi_bid, m_axi_bresp);
        m_axi_bvalid <= 0;
    endtask

    // ==============================
    //  Slave 任务：处理读事务
    // ==============================
    task automatic slave_handle_read;
        input string name;
        logic [7:0] len;
        int i;

        // 等待 AR 握手
        @(posedge clk);
        while (!(m_axi_arvalid && m_axi_arready))
            @(posedge clk);
        len = m_axi_arlen;
        $display("[%0t] %s AR: addr=0x%08h len=%0d", $time, name, m_axi_araddr, len);

        // 延迟后吐 R 数据
        repeat(2) @(posedge clk);
        for (i = 0; i <= len; i++) begin
            m_axi_rvalid <= 1;
            m_axi_rid    <= m_axi_arid;
            m_axi_rdata  <= 32'hA000_0000 + i;
            m_axi_rresp  <= 2'b00;
            m_axi_rlast  <= (i == len);
            @(posedge clk);
            while (!(m_axi_rvalid && m_axi_rready))
                @(posedge clk);
            $display("[%0t] %s R[%0d]: data=0x%08h last=%b", $time, name, i, m_axi_rdata, m_axi_rlast);
            m_axi_rvalid <= 0;
        end
    endtask

    // ==============================
    //  上游 Master 任务：发送写事务
    // ==============================
    task automatic master_do_write;
        input [A_WIDTH-1:0]  waddr;
        input [7:0]          wlen;      // AXI 约定 (burst_len 即 awlen)
        input [D_WIDTH-1:0]  base_data;
        int i;
        begin
            // 启动写
            @(posedge clk);
            start_write <= 1;
            addr        <= waddr;
            burst_len   <= wlen;
            id          <= 4'h1;
            @(posedge clk);
            start_write <= 0;

            // 等待可以发送数据
            @(posedge clk);
            for (i = 0; i <= wlen; i++) begin
                while (!wdata_ready)
                    @(posedge clk);
                wdata_valid <= 1;
                wdata_i     <= base_data + i;
                @(posedge clk);
                wdata_valid <= 0;
            end
        end
    endtask

    // ==============================
    //  上游 Master 任务：发送读事务
    // ==============================
    task automatic master_do_read;
        input [A_WIDTH-1:0]  raddr;
        input [7:0]          rlen;
        int i;
        begin
            // 启动读
            @(posedge clk);
            start_read <= 1;
            addr       <= raddr;
            burst_len  <= rlen;
            id         <= 4'h2;
            @(posedge clk);
            start_read <= 0;

            // 等待并接收读数据
            rdata_ready <= 1;
            for (i = 0; i <= rlen; i++) begin
                @(posedge clk);
                while (!rdata_valid)
                    @(posedge clk);
                $display("[%0t] CPU <---- R[%0d]: data=0x%08h", $time, i, rdata_o);
            end
            rdata_ready <= 0;
        end
    endtask

    // ==============================
    //  主测试序列
    // ==============================
    int pass_cnt, fail_cnt;

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        // 等待复位释放
        wait(rst_n);
        repeat(3) @(posedge clk);

        // =============================================
        //  TEST 1: 单次写 (4 beats)
        // =============================================
        $display("\n========== TEST 1: Single Write (4 beats) ==========");
        fork
            master_do_write(32'h0000_1000, 8'd3, 32'hCAFE_0000);
            slave_handle_write(8'd3, "WR1");
        join
        if (m_axi_bresp == 2'b00)
            $display("[PASS] TEST 1: write completed, bresp=OKAY\n");
        else begin
            $display("[FAIL] TEST 1: bresp=%b\n", m_axi_bresp);
            fail_cnt++;
        end

        repeat(3) @(posedge clk);

        // =============================================
        //  TEST 2: 单次读 (4 beats)
        // =============================================
        $display("========== TEST 2: Single Read (4 beats) ==========");
        fork
            master_do_read(32'h0000_1000, 8'd3);
            slave_handle_read("RD1");
        join
        $display("[PASS] TEST 2: read completed\n");

        repeat(3) @(posedge clk);

        // =============================================
        //  TEST 3: 读写并发
        // =============================================
        $display("========== TEST 3: Concurrent Read + Write ==========");
        fork
            master_do_write(32'h0000_2000, 8'd1, 32'hDEAD_BEEF);
            slave_handle_write(8'd1, "WR2");
        join_none

        fork
            master_do_read(32'h0000_3000, 8'd1);
            slave_handle_read("RD2");
        join

        wait(write_done);
        $display("[PASS] TEST 3: concurrent R/W completed\n");

        // =============================================
        //  总结果
        // =============================================
        $display("================= ALL TESTS DONE =================");
        $display("PASS: %0d  FAIL: %0d", 3 - fail_cnt, fail_cnt);
        $finish;
    end

    // ==============================
    //  超时保护
    // ==============================
    initial begin
        #100000;
        $display("[FAIL] TIMEOUT");
        $finish;
    end

    // ==============================
    //  基本断言
    // ==============================
    // valid 不应为 X
    always @(posedge clk) begin
        if (rst_n) begin
            if ($isunknown(m_axi_awvalid))
                $error("[%0t] m_axi_awvalid is X", $time);
            if ($isunknown(m_axi_wvalid))
                $error("[%0t] m_axi_wvalid is X", $time);
            if ($isunknown(m_axi_arvalid))
                $error("[%0t] m_axi_arvalid is X", $time);
        end
    end

    initial begin
                // 根据命令行参数决定是否dump波形
                    $display("Dumping waveform...");
                    $fsdbDumpfile();
                    $fsdbDumpvars();
                    $fsdbDumpMDA();
    end

endmodule
