// Compile/run the real bind file against an idle interface-only tb_top, not the DUT.
module tb_top;
    timeunit 1ns;
    timeprecision 1ps;
    real clock_period_ns = 10.0;
    logic clk = 0;
    logic rst_n = 1;
    wbb_interface wbb_vif(clk, rst_n);
    initial begin
        // 在本自测顶层读取时钟周期，再开始生成时钟，避免第一个半周期仍使用默认值。
        void'($value$plusargs("CLOCK_PERIOD_NS=%f", clock_period_ns));
        if (clock_period_ns <= 0) begin
            $fatal(1, "CLOCK_PERIOD_NS must be positive");
        end
        $display("BIND_CLOCK_CONFIG period_ns=%0.3f", clock_period_ns);
        forever begin
            #(clock_period_ns / 2);
            clk = ~clk;
        end
    end

    initial begin
        wbb_vif.reserve_en = 0;
        wbb_vif.reserve_addr = 0;
        wbb_vif.reserveOk = 1;
        wbb_vif.reserveSlot = 0;
        wbb_vif.push_en = 0;
        wbb_vif.push_slot = 0;
        wbb_vif.push_line = 0;
        wbb_vif.send_valid = 0;
        wbb_vif.send_ready = 0;
        wbb_vif.send_payload_addr = 0;
        wbb_vif.send_payload_wData = 0;
        wbb_vif.send_payload_id = 0;
        wbb_vif.memWriteResp_valid = 0;
        wbb_vif.memWriteResp_ready = 0;
        wbb_vif.memWriteResp_payload_id = 0;
        wbb_vif.full = 0;
        wbb_vif.q0Addr = 0;
        wbb_vif.q0Same = 0;
        wbb_vif.q1Addr = 0;
        wbb_vif.q1Same = 0;
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
        if (u_wbb_io_assertions.env_error_count != 0 || u_wbb_io_assertions.dut_error_count != 0) begin
            $fatal(1, "IO bind unexpectedly failed on idle trace");
        end
        $display("WBB_SVA_BIND_PASS");
        $finish;
    end
endmodule
