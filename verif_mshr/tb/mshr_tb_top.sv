`timescale 1ns/1ps
module mshr_tb_top;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import mshr_test_pkg::*;
    wire clk;
    wire rst_n;
    string test_name;
    clk_rst_interface clk_rst_vif(clk, rst_n);
    mshr_interface mshr_vif(clk, rst_n);

    // 生成器明确使用ASYNC/LOW，直接连接resetn，不保留高有效复位兼容取反。
    Mshr dut (
        .alloc_en(mshr_vif.alloc_en),
        .alloc_tag(mshr_vif.alloc_tag),
        .alloc_index(mshr_vif.alloc_index),
        .alloc_way(mshr_vif.alloc_way),
        .alloc_isWrite(mshr_vif.alloc_isWrite),
        .alloc_wData(mshr_vif.alloc_wData),
        .alloc_wordOff(mshr_vif.alloc_wordOff),
        .alloc_respId(mshr_vif.alloc_respId),
        .alloc_wbSlot(mshr_vif.alloc_wbSlot),
        .alloc_hasWb(mshr_vif.alloc_hasWb),
        .merge_en(mshr_vif.merge_en),
        .merge_entry(mshr_vif.merge_entry),
        .merge_isWrite(mshr_vif.merge_isWrite),
        .merge_wData(mshr_vif.merge_wData),
        .merge_wordOff(mshr_vif.merge_wordOff),
        .merge_respId(mshr_vif.merge_respId),
        .q0_tag(mshr_vif.q0_tag),
        .q0_index(mshr_vif.q0_index),
        .m0_hit(mshr_vif.m0_hit),
        .m0_entry(mshr_vif.m0_entry),
        .m0_mergeable(mshr_vif.m0_mergeable),
        .m0_slotFree(mshr_vif.m0_slotFree),
        .m0_freeSlot(mshr_vif.m0_freeSlot),
        .q1_tag(mshr_vif.q1_tag),
        .q1_index(mshr_vif.q1_index),
        .m1_hit(mshr_vif.m1_hit),
        .m1_entry(mshr_vif.m1_entry),
        .m1_mergeable(mshr_vif.m1_mergeable),
        .m1_slotFree(mshr_vif.m1_slotFree),
        .m1_freeSlot(mshr_vif.m1_freeSlot),
        .hasFree(mshr_vif.hasFree),
        .freeEntry(mshr_vif.freeEntry),
        .memReadReq_valid(mshr_vif.memReadReq_valid),
        .memReadReq_ready(mshr_vif.memReadReq_ready),
        .memReadReq_payload_addr(mshr_vif.memReadReq_payload_addr),
        .memReadReq_payload_id(mshr_vif.memReadReq_payload_id),
        .memReadResp_valid(mshr_vif.memReadResp_valid),
        .memReadResp_ready(mshr_vif.memReadResp_ready),
        .memReadResp_payload_rData(mshr_vif.memReadResp_payload_rData),
        .memReadResp_payload_id(mshr_vif.memReadResp_payload_id),
        .fill_en(mshr_vif.fill_en),
        .fill_index(mshr_vif.fill_index),
        .fill_way(mshr_vif.fill_way),
        .fill_tag(mshr_vif.fill_tag),
        .fill_dirty(mshr_vif.fill_dirty),
        .fill_line(mshr_vif.fill_line),
        .fillReady(mshr_vif.fillReady),
        .replay_valid(mshr_vif.replay_valid),
        .replay_ready(mshr_vif.replay_ready),
        .replay_payload_rData(mshr_vif.replay_payload_rData),
        .replay_payload_id(mshr_vif.replay_payload_id),
        .replay_payload_isWrite(mshr_vif.replay_payload_isWrite),
        .lockMask(mshr_vif.lockMask),
        .clk(clk),
        .resetn(rst_n)
    );
    mshr_io_assertions u_mshr_io_assertions(mshr_vif);

    initial begin
        clk_rst_config clock_cfg;
        real requested_clock_period;
        clock_cfg = clk_rst_config::type_id::create("clock_cfg");
        if ($value$plusargs("CLOCK_PERIOD_NS=%f", requested_clock_period)) begin
            clock_cfg.clock_period = requested_clock_period;
        end
        $display("TB_CLOCK_CONFIG period_ns=%0.3f initial_reset_cycles=%0d reset=ASYNC_LOW",
            clock_cfg.clock_period, clock_cfg.initial_reset_cycles);
        // 时钟配置只由TB顶层创建，随后test->env->clk_agent->driver逐级传递。
        uvm_config_db #(clk_rst_config)::set(null, "uvm_test_top", "clk_rst_config", clock_cfg);
        uvm_config_db #(virtual clk_rst_interface)::set(null, "*", "clk_rst_vif", clk_rst_vif);
        uvm_config_db #(virtual mshr_interface)::set(null, "*", "mshr_vif", mshr_vif);
        if ($value$plusargs("UVM_TESTNAME=%s", test_name) && test_name != "") begin
            run_test();
        end else begin
            run_test("mshr_base_test");
        end
    end
endmodule
