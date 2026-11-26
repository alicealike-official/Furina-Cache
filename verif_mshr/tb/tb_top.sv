`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import wbb_test_pkg::*;
    wire clk;
    wire rst_n;
    string test_name;
    clk_rst_interface clk_rst_vif(clk, rst_n);
    wbb_interface wbb_vif(clk, rst_n);

    WriteBackBuffer dut (
        .clk(clk),
        .resetn(rst_n),
        .reserve_en(wbb_vif.reserve_en),
        .reserve_addr(wbb_vif.reserve_addr),
        .push_en(wbb_vif.push_en),
        .push_slot(wbb_vif.push_slot),
        .push_line(wbb_vif.push_line),
        .send_ready(wbb_vif.send_ready),
        .memWriteResp_valid(wbb_vif.memWriteResp_valid),
        .memWriteResp_payload_id(wbb_vif.memWriteResp_payload_id),
        .q0Addr(wbb_vif.q0Addr),
        .q1Addr(wbb_vif.q1Addr),
        .reserveOk(wbb_vif.reserveOk),
        .reserveSlot(wbb_vif.reserveSlot),
        .send_valid(wbb_vif.send_valid),
        .send_payload_addr(wbb_vif.send_payload_addr),
        .send_payload_wData(wbb_vif.send_payload_wData),
        .send_payload_id(wbb_vif.send_payload_id),
        .memWriteResp_ready(wbb_vif.memWriteResp_ready),
        .full(wbb_vif.full),
        .q0Same(wbb_vif.q0Same),
        .q1Same(wbb_vif.q1Same)
    );

    initial begin
        clk_rst_config clock_cfg;
        real requested_clock_period;

        // 时钟配置只在 TB 顶层创建，使用配置类中的默认周期和启动复位拍数。
        // 先传给 test，再由 test、env 和 clock agent 逐级传给 clock driver。
        clock_cfg = clk_rst_config::type_id::create("clock_cfg");
        // 时钟本身需要实际时间单位；协议等待均按拍数计，不再用这个周期换算响应延迟。
        if ($value$plusargs("CLOCK_PERIOD_NS=%f", requested_clock_period)) begin
            clock_cfg.clock_period = requested_clock_period;
        end
        $display("TB_CLOCK_CONFIG period_ns=%0.3f initial_reset_cycles=%0d",
            clock_cfg.clock_period, clock_cfg.initial_reset_cycles);
        uvm_config_db #(clk_rst_config)::set(null, "uvm_test_top", "clk_rst_config", clock_cfg);
        uvm_config_db #(virtual clk_rst_interface)::set(null, "*", "clk_rst_vif", clk_rst_vif);
        uvm_config_db #(virtual wbb_interface)::set(null, "*", "wbb_vif", wbb_vif);
        if ($value$plusargs("UVM_TESTNAME=%s", test_name) && test_name != "") begin
            run_test();
        end else begin
            run_test("wbb_base_test");
        end
    end
endmodule
