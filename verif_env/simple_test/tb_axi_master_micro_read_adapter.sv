// `timescale 1ns / 1ps

// module tb_axi_master_micro_read_adapter_smoke;

//     //======================== Parameters ====================//
//     localparam AXI_DATA_WIDTH  = 32;
//     localparam AXI_ADDR_WIDTH  = 32;
//     localparam AXI_ID_WIDTH    = 4;
//     localparam AXI_BURST_LEN   = 16;
//     localparam MAX_OSD         = 4;
//     localparam CLK_PERIOD      = 10;

//     //======================== Signals =======================//
//     logic                               rd_req_valid;
//     logic [AXI_ADDR_WIDTH-1:0]          addr;
//     logic [7:0]                         burst_len;
//     logic [2:0]                         burst_size;
//     logic [1:0]                         burst_type;
//     logic [AXI_ID_WIDTH-1:0]            id;
//     logic                               rd_req_ready;

//     logic [AXI_DATA_WIDTH-1:0]          rdata_o;
//     logic                               rdata_valid;
//     logic                               rdata_ready;

//     logic                               read_done;
//     logic [1:0]                         error_resp;

//     logic                               axi_aclk;
//     logic                               axi_aresetn;

//     logic [AXI_ID_WIDTH-1:0]            m_axi_arid;
//     logic [AXI_ADDR_WIDTH-1:0]          m_axi_araddr;
//     logic [7:0]                         m_axi_arlen;
//     logic [2:0]                         m_axi_arsize;
//     logic [1:0]                         m_axi_arburst;
//     logic                               m_axi_arlock;
//     logic [2:0]                         m_axi_arprot;
//     logic [3:0]                         m_axi_arqos;
//     logic [3:0]                         m_axi_arregion;
//     logic [3:0]                         m_axi_arcache;
//     logic                               m_axi_arvalid;
//     logic                               m_axi_arready;

//     logic [AXI_ID_WIDTH-1:0]            m_axi_rid;
//     logic [AXI_DATA_WIDTH-1:0]          m_axi_rdata;
//     logic [1:0]                         m_axi_rresp;
//     logic                               m_axi_rlast;
//     logic                               m_axi_rvalid;
//     logic                               m_axi_rready;

//     //======================== DUT Instance ==================//
//     axi_master_micro_read_adapter #(
//         .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
//         .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
//         .AXI_ID_WIDTH   (AXI_ID_WIDTH),
//         .AXI_BURST_LEN  (AXI_BURST_LEN),
//         .MAX_OSD        (MAX_OSD)
//     ) u_dut (
//         .rd_req_valid     (rd_req_valid),
//         .addr           (addr),
//         .burst_len      (burst_len),
//         .burst_size     (burst_size),
//         .burst_type     (burst_type),
//         .id             (id),
//         .rd_req_ready   (rd_req_ready),
//         .rdata_o        (rdata_o),
//         .rdata_valid    (rdata_valid),
//         .rdata_ready    (rdata_ready),
//         .read_done      (read_done),
//         .error_resp     (error_resp),
//         .axi_aclk       (axi_aclk),
//         .axi_aresetn    (axi_aresetn),
//         .m_axi_arid     (m_axi_arid),
//         .m_axi_araddr   (m_axi_araddr),
//         .m_axi_arlen    (m_axi_arlen),
//         .m_axi_arsize   (m_axi_arsize),
//         .m_axi_arburst  (m_axi_arburst),
//         .m_axi_arlock   (m_axi_arlock),
//         .m_axi_arprot   (m_axi_arprot),
//         .m_axi_arqos    (m_axi_arqos),
//         .m_axi_arregion (m_axi_arregion),
//         .m_axi_arcache  (m_axi_arcache),
//         .m_axi_arvalid  (m_axi_arvalid),
//         .m_axi_arready  (m_axi_arready),
//         .m_axi_rid      (m_axi_rid),
//         .m_axi_rdata    (m_axi_rdata),
//         .m_axi_rresp    (m_axi_rresp),
//         .m_axi_rlast    (m_axi_rlast),
//         .m_axi_rvalid   (m_axi_rvalid),
//         .m_axi_rready   (m_axi_rready)
//     );

//     //======================== Clock & Reset =================//
//     initial begin
//         axi_aclk = 0;
//         forever #(CLK_PERIOD/2) axi_aclk = ~axi_aclk;
//     end

//     initial begin
//         axi_aresetn = 0;
//         repeat(5) @(posedge axi_aclk);
//         axi_aresetn = 1;
//     end

//     //======================== Simple AXI Slave ==============//
//     // Memory (word addressed, 32-bit wide)
//     logic [31:0] mem [0:255];
//     initial begin
//         for (int i = 0; i < 256; i++) begin
//             mem[i] = i * 4;   // 0,4,8,12,...
//         end
//     end

//     // Fixed slave behavior: always ready, respond in order
//     assign m_axi_arready = 1'b1;      // always accept commands
//     logic [7:0]  r_len;
//     logic [31:0] r_addr;
//     logic [7:0]  r_beat_cnt;
//     logic        r_active;

//     always @(posedge axi_aclk or negedge axi_aresetn) begin
//         if (!axi_aresetn) begin
//             r_active   <= 0;
//             r_len      <= 0;
//             r_addr     <= 0;
//             r_beat_cnt <= 0;
//             m_axi_rvalid <= 0;
//             m_axi_rlast  <= 0;
//         end 
        
//         else begin
//             // Latch AR when valid & ready
//             if (m_axi_arvalid && m_axi_arready) begin
//                 r_active   <= 1;
//                 r_len      <= m_axi_arlen;        // burst len-1
//                 r_addr     <= m_axi_araddr;
//                 r_beat_cnt <= 0;
//             end

//             // Drive R channel
//             if (r_active && m_axi_rready) begin
//                 // Provide data
//                 m_axi_rvalid <= 1'b1;
//                 m_axi_rid    <= m_axi_arid;        // echo ID from AR (assume same ID)
//                 m_axi_rresp  <= (r_addr >= 32'h1000) ? 2'b10 : 2'b00; // error test
//                 m_axi_rdata  <= mem[r_addr[31:2] + r_beat_cnt];       // word address
//                 m_axi_rlast  <= (r_beat_cnt == r_len+1);

//                 if (r_beat_cnt == r_len+1) begin
//                     r_active <= 0;   // burst done
//                 end else begin
//                     r_beat_cnt <= r_beat_cnt + 1;
//                     r_addr     <= r_addr + (1 << m_axi_arsize);
//                 end
//             end else if (r_active && !m_axi_rready) begin
//                 // Stall: keep valid high, data stays
//                 m_axi_rvalid <= 1'b1;
//             end else begin
//                 m_axi_rvalid <= 1'b0;
//             end
//         end
//     end

//     //======================== Transaction Side Tie-offs =====//
//     // rdata_ready: always ready for smoke test
//     assign rdata_ready = 1'b1;

//     //======================== Simple Test Tasks =============//
//     task automatic send_read(
//         input [31:0] a,
//         input [7:0]  len,
//         input [2:0]  size,
//         input [1:0]  burst,
//         input [3:0]  tid
//     );
//         // Wait until module can accept command
//         while (!rd_req_ready) @(posedge axi_aclk);
//         addr       = a;
//         burst_len  = len;       // note: burst_len input of DUT is actual length-1?
//                                 // The port name is burst_len, but typical AXI signals use len = beats-1.
//                                 // We will assume the DUT expects the AXI arlen value (beats-1).
//                                 // So passing len = 3 means 4 beats.
//         burst_size = size;
//         burst_type = burst;
//         id         = tid;
//         rd_req_valid = 1;
//         @(posedge axi_aclk);
//         rd_req_valid = 0;
//     endtask

//     task automatic wait_read_done();
//         while (!read_done) @(posedge axi_aclk);
//     endtask

//     //======================== Main Test Sequence ============//
//     initial begin
//         // Defaults
//         rd_req_valid  = 0;
//         addr        = 0;
//         burst_len   = 0;
//         burst_size  = 3'b010;   // 4 bytes per beat
//         burst_type  = 2'b01;    // INCR
//         id          = 0;

//         // Wait for reset deassertion
//         @(posedge axi_aresetn);
//         repeat(5) @(posedge axi_aclk);

//         // $display("==============================================");
//         // $display(" Smoke Test 1: Single read burst (4 beats)");
//         // $display("==============================================");
//         // send_read(32'h0000_0000, 3, 3'b010, 2'b01, 4'h0);  // len=3 -> 4 beats
//         // fork
//         //     begin
//         //         // Collect and check data manually
//         //         for (int i=0; i<4; i++) begin
//         //             while (!rdata_valid) @(posedge axi_aclk);
//         //             $display("[%0t] Data beat %0d: 0x%08h", $time, i, rdata_o);
//         //             if (rdata_o !== mem[0+2*i]) begin
//         //                 $error("Data mismatch at beat %0d: got 0x%08h, expected 0x%08h",
//         //                        i, rdata_o, mem[0+2*i]);
//         //             end
//         //             @(posedge axi_aclk); // consume beat
//         //         end
//         //     end
//         //     wait_read_done();
//         // join
//         // $display("Smoke Test 1 PASSED\n");

//         // $display("==============================================");
//         // $display(" Smoke Test 2: Two back-to-back short bursts");
//         // $display("==============================================");
//         // // Send first burst
//         // send_read(32'h0000_0020, 1, 3'b010, 2'b01, 4'h1);  // len=1 -> 2 beats
//         // // Collect its data (2 beats)
//         // for (int i=0; i<2; i++) begin
//         //     // while (!rdata_valid) @(posedge axi_aclk);
//         //     do begin
//         //         @(posedge axi_aclk);
//         //     end while(!rdata_valid);
//         //     $display("[%0t] Burst1 beat %0d: 0x%08h", $time, i, rdata_o);
//         //     if (rdata_o !== mem[8+2*i])  // addr 0x20 -> word addr 8
//         //         $error("Burst1 data mismatch");
//         //     //@(posedge axi_aclk);
//         // end
//         // wait_read_done();

//         // // Send second burst immediately
//         // send_read(32'h0000_0040, 2, 3'b010, 2'b01, 4'h2);  // len=2 -> 3 beats
//         // for (int i=0; i<3; i++) begin
//         //     // while (!rdata_valid) @(posedge axi_aclk);
//         //     do begin
//         //         @(posedge axi_aclk);
//         //     end while(!rdata_valid);
//         //     $display("[%0t] Burst2 beat %0d: 0x%08h", $time, i, rdata_o);
//         //     if (rdata_o !== mem[16+2*i]) // addr 0x40 -> word addr 16
//         //         $error("Burst2 data mismatch");
//         //     //@(posedge axi_aclk);
//         // end
//         // wait_read_done();
//         // $display("Smoke Test 2 PASSED\n");

//         // $display("==============================================");
//         // $display(" Smoke Test 3: Error response (addr >= 0x1000)");
//         // $display("==============================================");
//         // send_read(32'h0000_1000, 0, 3'b010, 2'b01, 4'hA);  // single beat to error region
//         // wait_read_done();
//         // if (error_resp !== 2'b10) begin
//         //     $error("Expected SLVERR (2'b10), got %b", error_resp);
//         // end else begin
//         //     $display("Error response correct: SLVERR");
//         // end
//         // // There will be one data beat (may be garbage), but we don't check data
//         // // Consume it anyway
//         // if (rdata_valid) @(posedge axi_aclk);
//         // $display("Smoke Test 3 PASSED\n");
//         // ---------------------------------------------------------------
// // Smoke Test 4: Outstanding reads (send 3 cmds, wait all done)
// // Each cmd: len=1 (2 beats), different addresses
// // ---------------------------------------------------------------
//         $display("==============================================");
//         $display(" Smoke Test 4: Outstanding reads (3 commands)");
//         $display("==============================================");
//         // 连续发送，不等待前一个 done
//         begin
//             send_read(32'h0000_0080, 1, 3'b010, 2'b01, 4'h3);  // addr 0x80 -> word 32,33
//             //@(posedge axi_aclk);
//             send_read(32'h0000_00A0, 1, 3'b010, 2'b01, 4'h4);  // addr 0xA0 -> word 40,41
//             //send_read(32'h0000_00C0, 1, 3'b010, 2'b01, 4'h5);  // addr 0xC0 -> word 48,49
//         end
//         // 等待所有三个事务完成并检查数据
//         repeat(3) begin
//             wait_read_done();
//             // 每个事务完成时 error_resp 应为 0
//             if (error_resp !== 2'b00)
//                 $error("Unexpected error in outstanding test, error_resp=%b", error_resp);
//         end
//         // 数据在过程中由之前的 per-beat 检查验证（但原 TB 只对单个事务做了内联检查）。
//         // 为了简单，这里不加入复杂的 per-transaction checker，仅通过 read_done 和 error_resp 确认。
//         // 如需严格比对数据，可参考之前复杂 TB 中的队列记录方法。
//         $display("Smoke Test 4 PASSED\n");

//         $display("==============================================");
//         $display(" All smoke tests completed successfully.");
//         $display("==============================================");
//         #(10*CLK_PERIOD);
//         $finish;
//     end

//     // Timeout
//     initial begin
//         #500000;
//         $error("Global timeout!");
//         $finish;
//     end

//     initial begin
//                 // 根据命令行参数决定是否dump波形
//                 $display("Dumping waveform...");
//                 $fsdbDumpfile();
//                 $fsdbDumpvars();
//                 $fsdbDumpMDA();
//     end

// endmodule

`timescale 1ns / 1ps

module tb_outstanding_smoke;

    localparam DATA_W = 32;
    localparam ADDR_W = 32;
    localparam ID_W   = 4;
    localparam CLK_HALF = 5;   // 100 MHz

    // ---- DUT I/O ----
    logic               rd_req_valid, rd_req_ready;
    logic [ADDR_W-1:0]  addr;
    logic [7:0]         burst_len;
    logic [2:0]         burst_size;
    logic [1:0]         burst_type;
    logic [ID_W-1:0]    id;
    logic [DATA_W-1:0]  rdata_o;
    logic               rdata_valid, rdata_ready;
    logic               read_done;
    logic [1:0]         error_resp;

    logic               axi_aclk, axi_aresetn;
    logic [ID_W-1:0]    m_axi_arid;
    logic [ADDR_W-1:0]  m_axi_araddr;
    logic [7:0]         m_axi_arlen;
    logic [2:0]         m_axi_arsize;
    logic [1:0]         m_axi_arburst;
    logic               m_axi_arlock, m_axi_arvalid, m_axi_arready;
    logic [2:0]         m_axi_arprot;
    logic [3:0]         m_axi_arqos, m_axi_arregion, m_axi_arcache;
    logic [ID_W-1:0]    m_axi_rid;
    logic [DATA_W-1:0]  m_axi_rdata;
    logic [1:0]         m_axi_rresp;
    logic               m_axi_rlast, m_axi_rvalid, m_axi_rready;

    // ---- DUT ----
    axi_master_micro_read_adapter #(
        .AXI_DATA_WIDTH (DATA_W),
        .AXI_ADDR_WIDTH (ADDR_W),
        .AXI_ID_WIDTH   (ID_W),
        .AXI_BURST_LEN  (16),
        .MAX_OSD        (4)
    ) dut (.*);

    // ---- Clock & Reset ----
    initial begin
        axi_aclk = 0;
        forever #(CLK_HALF) axi_aclk = ~axi_aclk;
    end
    initial begin
        axi_aresetn = 0;
        repeat(5) @(posedge axi_aclk);
        axi_aresetn = 1;
    end

    // ---- Simple AXI Slave with Command Queue (for outstanding) ----
    logic [DATA_W-1:0] mem [0:255];
    initial begin
        for (int i = 0; i < 256; i++) mem[i] = i * 4;   // 0,4,8,...
    end

    // Command queue
    typedef struct {
        logic [7:0]  len;
        logic [31:0] addr;
        logic [3:0]  id;
    } ar_t;
    ar_t ar_q[$];

    assign m_axi_arready = 1'b1;   // never backpressure

    always @(posedge axi_aclk) begin
        if (!axi_aresetn) begin
            ar_q.delete();
        end else begin
            if (m_axi_arvalid && m_axi_arready)
                ar_q.push_back('{m_axi_arlen, m_axi_araddr, m_axi_arid});
        end
    end

    // R channel FSM (one burst at a time, sequential)
    logic [7:0]  r_len, r_cnt;
    logic [31:0] r_addr;
    logic        r_active;
    always @(posedge axi_aclk) begin
        if (!axi_aresetn) begin
            r_active   <= 0;
            m_axi_rvalid <= 0;
        end else begin
            // Start new burst if idle and queue not empty
            if (!r_active && ar_q.size() > 0) begin
                automatic ar_t c = ar_q.pop_front();
                r_active   <= 1;
                r_len      <= c.len;
                r_addr     <= c.addr;
                r_cnt      <= 0;
                m_axi_rid   <= c.id;
                m_axi_rdata <= mem[c.addr[31:2]];
                m_axi_rresp <= (c.addr >= 32'h1000) ? 2'b10 : 2'b00;
                m_axi_rlast <= (c.len == 0);
                m_axi_rvalid <= 1;
                if (c.len != 0) begin
                    r_addr <= c.addr + (1 << m_axi_arsize);
                    r_cnt  <= 1;
                end else begin
                    r_active <= 0; // single beat done immediately
                end
            end
            // Continue burst
            else if (r_active && m_axi_rready) begin
                if (r_cnt == r_len+1) begin
                    r_active <= 0;
                    m_axi_rvalid <= 0;
                end 
                
                else begin
                    m_axi_rdata <= mem[r_addr[31:2]];
                    m_axi_rresp <= (r_addr >= 32'h1000) ? 2'b10 : 2'b00;
                    m_axi_rlast <= (r_cnt == r_len);
                    m_axi_rvalid <= 1;
                    r_addr <= r_addr + (1 << m_axi_arsize);
                    r_cnt  <= r_cnt + 1;
                end
            end
        end
    end

    // ---- Consumer side ----
    assign rdata_ready = 1'b1;   // always ready to take data

    // ---- Test Helpers ----
    task send_read(input [31:0] a, input [7:0] len, input [3:0] tid);
        while (!rd_req_ready) @(posedge axi_aclk);
        addr       = a;
        burst_len  = len;        // beats-1
        burst_size = 3'b010;     // 4 bytes per beat
        burst_type = 2'b01;      // INCR
        id         = tid;
        rd_req_valid = 1;
        @(posedge axi_aclk);
        rd_req_valid = 0;
    endtask

    task wait_done(int N);
        repeat(N) @(posedge axi_aclk iff read_done);
    endtask

    // ---- Expected data checker ----
    // We'll build a queue of all expected data words for all issued commands.
    logic [DATA_W-1:0] exp_q[$];

    task push_expected(input [31:0] a, input [7:0] len);
        for (int i = 0; i <= len; i++)   // len = beats-1, so len+1 beats
            exp_q.push_back(mem[a[31:2] + i]);
    endtask

    // Check every received beat against expected queue
    always @(posedge axi_aclk) begin
        if (axi_aresetn && rdata_valid && rdata_ready) begin
            if (exp_q.size() == 0) begin
                $error("[%0t] Unexpected data beat: 0x%08h", $time, rdata_o);
            end else begin
                automatic logic [DATA_W-1:0] exp = exp_q.pop_front();
                if (rdata_o !== exp) begin
                    $error("[%0t] Data mismatch: got 0x%08h, expected 0x%08h", $time, rdata_o, exp);
                end else begin
                    $display("[%0t] Data OK: 0x%08h", $time, rdata_o);
                end
            end
        end
    end

    // ---- Main Test (Outstanding only) ----
    initial begin
        rd_req_valid = 0;
        addr       = 0;
        burst_len  = 0;
        burst_size = 3'b010;
        burst_type = 2'b01;
        id         = 0;

        @(posedge axi_aresetn);
        repeat(5) @(posedge axi_aclk);

        $display("=== Outstanding test: 3 back-to-back commands ===");

        // Prepare expected data for all commands BEFORE issuing
        push_expected(32'h80, 1);   // len=1 → 2 beats: mem[32]=128, mem[33]=132
        push_expected(32'hA0, 1);   // len=1 → 2 beats: mem[40]=160, mem[41]=164
        push_expected(32'hC0, 1);   // len=1 → 2 beats: mem[48]=192, mem[49]=196

        begin
            send_read(32'h80, 1, 3);
            send_read(32'hA0, 1, 4);
            send_read(32'hC0, 1, 5);
        end

        // Wait for all three transactions to complete
        wait_done(3);
        $display("All done. Expected data queue empty? %s", exp_q.size() ? "FAIL" : "OK");

        if (exp_q.size() != 0)
            $error("Not all expected data was received!");

        $display("=== Outstanding test PASSED ===");
        #(10*CLK_HALF*2) $finish;
    end

    initial begin
                // 根据命令行参数决定是否dump波形
                $display("Dumping waveform...");
                $fsdbDumpfile();
                $fsdbDumpvars();
                $fsdbDumpMDA();
    end

endmodule