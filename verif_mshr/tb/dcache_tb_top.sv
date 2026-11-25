`timescale 1ns/1ps
module dcache_tb_top;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import dcache_test_pkg::*;
    wire clk;
    wire rst_n;
    string test_name;
    clk_rst_interface clk_rst_vif(clk, rst_n);
    dcache_interface dcache_vif(clk, rst_n);
    DCache dut (
        .cpu_valid(dcache_vif.cpu_valid),
        .cpu_ready(dcache_vif.cpu_ready),
        .cpu_payload_addr(dcache_vif.cpu_payload_addr),
        .cpu_payload_wrEn(dcache_vif.cpu_payload_wrEn),
        .cpu_payload_wData(dcache_vif.cpu_payload_wData),
        .cpu_payload_id(dcache_vif.cpu_payload_id),
        .cpuReadResp_valid(dcache_vif.cpuReadResp_valid),
        .cpuReadResp_ready(dcache_vif.cpuReadResp_ready),
        .cpuReadResp_payload_rData(dcache_vif.cpuReadResp_payload_rData),
        .cpuReadResp_payload_id(dcache_vif.cpuReadResp_payload_id),
        .cpuWriteResp_valid(dcache_vif.cpuWriteResp_valid),
        .cpuWriteResp_ready(dcache_vif.cpuWriteResp_ready),
        .cpuWriteResp_payload_id(dcache_vif.cpuWriteResp_payload_id),
        .memReadReq_valid(dcache_vif.memReadReq_valid),
        .memReadReq_ready(dcache_vif.memReadReq_ready),
        .memReadReq_payload_addr(dcache_vif.memReadReq_payload_addr),
        .memReadReq_payload_id(dcache_vif.memReadReq_payload_id),
        .memWriteReq_valid(dcache_vif.memWriteReq_valid),
        .memWriteReq_ready(dcache_vif.memWriteReq_ready),
        .memWriteReq_payload_addr(dcache_vif.memWriteReq_payload_addr),
        .memWriteReq_payload_wData(dcache_vif.memWriteReq_payload_wData),
        .memWriteReq_payload_id(dcache_vif.memWriteReq_payload_id),
        .memReadResp_valid(dcache_vif.memReadResp_valid),
        .memReadResp_ready(dcache_vif.memReadResp_ready),
        .memReadResp_payload_rData(dcache_vif.memReadResp_payload_rData),
        .memReadResp_payload_id(dcache_vif.memReadResp_payload_id),
        .memWriteResp_valid(dcache_vif.memWriteResp_valid),
        .memWriteResp_ready(dcache_vif.memWriteResp_ready),
        .memWriteResp_payload_id(dcache_vif.memWriteResp_payload_id),
        .clk(clk),
        .resetn(rst_n)
    );
    dcache_io_assertions assertions(dcache_vif);
    initial begin
        clk_rst_config clock_cfg;
        real period_ns;
`ifdef DCACHE_PORT_STUB
        $fatal(1, "Port stub is compile-only; real DUT required for simulation");
`endif
        clock_cfg = clk_rst_config::type_id::create("clock_cfg");
        if ($value$plusargs("CLOCK_PERIOD_NS=%f", period_ns)) clock_cfg.clock_period = period_ns;
        uvm_config_db #(clk_rst_config)::set(null, "uvm_test_top", "clk_rst_config", clock_cfg);
        uvm_config_db #(virtual clk_rst_interface)::set(null, "*", "clk_rst_vif", clk_rst_vif);
        uvm_config_db #(virtual dcache_interface)::set(null, "*", "dcache_vif", dcache_vif);
        if ($value$plusargs("UVM_TESTNAME=%s", test_name) && test_name != "") run_test();
        else run_test("dcache_base_test");
    end
endmodule
