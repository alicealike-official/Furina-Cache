`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import wbb_test_pkg::*;
    wire clk;
    wire rst_n;
    string test_name;
    clk_rst_interface clk_rst_vif(clk, rst_n);
    wbb_interface wbb_vif(clk, rst_n);

    WriteBackBuffer dut (
        .clk(clk),
        .reset(~rst_n),
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
        uvm_config_db #(virtual clk_rst_interface)::set(null, "*", "clk_rst_vif", clk_rst_vif);
        uvm_config_db #(virtual wbb_interface)::set(null, "*", "wbb_vif", wbb_vif);
        if ($value$plusargs("UVM_TESTNAME=%s", test_name) && test_name != "") begin
            run_test();
        end else begin
            run_test("wbb_base_test");
        end
    end
endmodule
