// 只读IP接入：所有层级路径集中于本文件末尾，复用原IP interface/monitor/sample/SVA。
module dcache_ip_bind(
    input wire clk,
    input wire rst_n,
    input wire  mshr_alloc_en,
    input wire [mshr_params_pkg::TAG_WIDTH-1:0] mshr_alloc_tag,
    input wire [mshr_params_pkg::INDEX_WIDTH-1:0] mshr_alloc_index,
    input wire [mshr_params_pkg::WAY_WIDTH-1:0] mshr_alloc_way,
    input wire  mshr_alloc_isWrite,
    input wire [mshr_params_pkg::DATA_WIDTH-1:0] mshr_alloc_wData,
    input wire [mshr_params_pkg::WORD_OFF_WIDTH-1:0] mshr_alloc_wordOff,
    input wire [mshr_params_pkg::CPU_ID_WIDTH-1:0] mshr_alloc_respId,
    input wire [mshr_params_pkg::WBB_SLOT_WIDTH-1:0] mshr_alloc_wbSlot,
    input wire  mshr_alloc_hasWb,
    input wire  mshr_merge_en,
    input wire [mshr_params_pkg::ENTRY_WIDTH-1:0] mshr_merge_entry,
    input wire  mshr_merge_isWrite,
    input wire [mshr_params_pkg::DATA_WIDTH-1:0] mshr_merge_wData,
    input wire [mshr_params_pkg::WORD_OFF_WIDTH-1:0] mshr_merge_wordOff,
    input wire [mshr_params_pkg::CPU_ID_WIDTH-1:0] mshr_merge_respId,
    input wire [mshr_params_pkg::TAG_WIDTH-1:0] mshr_q0_tag,
    input wire [mshr_params_pkg::INDEX_WIDTH-1:0] mshr_q0_index,
    input wire [mshr_params_pkg::TAG_WIDTH-1:0] mshr_q1_tag,
    input wire [mshr_params_pkg::INDEX_WIDTH-1:0] mshr_q1_index,
    input wire  mshr_m0_hit,
    input wire [mshr_params_pkg::ENTRY_WIDTH-1:0] mshr_m0_entry,
    input wire  mshr_m0_mergeable,
    input wire  mshr_m0_slotFree,
    input wire [mshr_params_pkg::SLOT_WIDTH-1:0] mshr_m0_freeSlot,
    input wire  mshr_m1_hit,
    input wire [mshr_params_pkg::ENTRY_WIDTH-1:0] mshr_m1_entry,
    input wire  mshr_m1_mergeable,
    input wire  mshr_m1_slotFree,
    input wire [mshr_params_pkg::SLOT_WIDTH-1:0] mshr_m1_freeSlot,
    input wire  mshr_hasFree,
    input wire [mshr_params_pkg::ENTRY_WIDTH-1:0] mshr_freeEntry,
    input wire  mshr_memReadReq_valid,
    input wire  mshr_memReadReq_ready,
    input wire [mshr_params_pkg::ADDR_WIDTH-1:0] mshr_memReadReq_payload_addr,
    input wire [mshr_params_pkg::BUS_ID_WIDTH-1:0] mshr_memReadReq_payload_id,
    input wire  mshr_memReadResp_valid,
    input wire  mshr_memReadResp_ready,
    input wire [mshr_params_pkg::LINE_WIDTH-1:0] mshr_memReadResp_payload_rData,
    input wire [mshr_params_pkg::BUS_ID_WIDTH-1:0] mshr_memReadResp_payload_id,
    input wire  mshr_fill_en,
    input wire [mshr_params_pkg::INDEX_WIDTH-1:0] mshr_fill_index,
    input wire [mshr_params_pkg::WAY_WIDTH-1:0] mshr_fill_way,
    input wire [mshr_params_pkg::TAG_WIDTH-1:0] mshr_fill_tag,
    input wire  mshr_fill_dirty,
    input wire [mshr_params_pkg::LINE_WIDTH-1:0] mshr_fill_line,
    input wire  mshr_fillReady,
    input wire  mshr_replay_valid,
    input wire  mshr_replay_ready,
    input wire [mshr_params_pkg::DATA_WIDTH-1:0] mshr_replay_payload_rData,
    input wire [mshr_params_pkg::CPU_ID_WIDTH-1:0] mshr_replay_payload_id,
    input wire  mshr_replay_payload_isWrite,
    input wire [mshr_params_pkg::LOCK_WIDTH-1:0] mshr_lockMask,
    input wire  wbb_reserve_en,
    input wire [wbb_params_pkg::ADDR_WIDTH-1:0] wbb_reserve_addr,
    input wire  wbb_push_en,
    input wire [wbb_params_pkg::SLOT_WIDTH-1:0] wbb_push_slot,
    input wire [wbb_params_pkg::LINE_WIDTH-1:0] wbb_push_line,
    input wire  wbb_send_ready,
    input wire  wbb_memWriteResp_valid,
    input wire [wbb_params_pkg::BUS_ID_WIDTH-1:0] wbb_memWriteResp_payload_id,
    input wire [wbb_params_pkg::ADDR_WIDTH-1:0] wbb_q0Addr,
    input wire [wbb_params_pkg::ADDR_WIDTH-1:0] wbb_q1Addr,
    input wire  wbb_reserveOk,
    input wire [wbb_params_pkg::SLOT_WIDTH-1:0] wbb_reserveSlot,
    input wire  wbb_send_valid,
    input wire [wbb_params_pkg::ADDR_WIDTH-1:0] wbb_send_payload_addr,
    input wire [wbb_params_pkg::LINE_WIDTH-1:0] wbb_send_payload_wData,
    input wire [wbb_params_pkg::BUS_ID_WIDTH-1:0] wbb_send_payload_id,
    input wire  wbb_memWriteResp_ready,
    input wire  wbb_full,
    input wire  wbb_q0Same,
    input wire  wbb_q1Same
);
    import uvm_pkg::*;
    mshr_interface mshr_vif(clk, rst_n);
    wbb_interface wbb_vif(clk, rst_n);
    assign mshr_vif.alloc_en = mshr_alloc_en;
    assign mshr_vif.alloc_tag = mshr_alloc_tag;
    assign mshr_vif.alloc_index = mshr_alloc_index;
    assign mshr_vif.alloc_way = mshr_alloc_way;
    assign mshr_vif.alloc_isWrite = mshr_alloc_isWrite;
    assign mshr_vif.alloc_wData = mshr_alloc_wData;
    assign mshr_vif.alloc_wordOff = mshr_alloc_wordOff;
    assign mshr_vif.alloc_respId = mshr_alloc_respId;
    assign mshr_vif.alloc_wbSlot = mshr_alloc_wbSlot;
    assign mshr_vif.alloc_hasWb = mshr_alloc_hasWb;
    assign mshr_vif.merge_en = mshr_merge_en;
    assign mshr_vif.merge_entry = mshr_merge_entry;
    assign mshr_vif.merge_isWrite = mshr_merge_isWrite;
    assign mshr_vif.merge_wData = mshr_merge_wData;
    assign mshr_vif.merge_wordOff = mshr_merge_wordOff;
    assign mshr_vif.merge_respId = mshr_merge_respId;
    assign mshr_vif.q0_tag = mshr_q0_tag;
    assign mshr_vif.q0_index = mshr_q0_index;
    assign mshr_vif.q1_tag = mshr_q1_tag;
    assign mshr_vif.q1_index = mshr_q1_index;
    assign mshr_vif.m0_hit = mshr_m0_hit;
    assign mshr_vif.m0_entry = mshr_m0_entry;
    assign mshr_vif.m0_mergeable = mshr_m0_mergeable;
    assign mshr_vif.m0_slotFree = mshr_m0_slotFree;
    assign mshr_vif.m0_freeSlot = mshr_m0_freeSlot;
    assign mshr_vif.m1_hit = mshr_m1_hit;
    assign mshr_vif.m1_entry = mshr_m1_entry;
    assign mshr_vif.m1_mergeable = mshr_m1_mergeable;
    assign mshr_vif.m1_slotFree = mshr_m1_slotFree;
    assign mshr_vif.m1_freeSlot = mshr_m1_freeSlot;
    assign mshr_vif.hasFree = mshr_hasFree;
    assign mshr_vif.freeEntry = mshr_freeEntry;
    assign mshr_vif.memReadReq_valid = mshr_memReadReq_valid;
    assign mshr_vif.memReadReq_ready = mshr_memReadReq_ready;
    assign mshr_vif.memReadReq_payload_addr = mshr_memReadReq_payload_addr;
    assign mshr_vif.memReadReq_payload_id = mshr_memReadReq_payload_id;
    assign mshr_vif.memReadResp_valid = mshr_memReadResp_valid;
    assign mshr_vif.memReadResp_ready = mshr_memReadResp_ready;
    assign mshr_vif.memReadResp_payload_rData = mshr_memReadResp_payload_rData;
    assign mshr_vif.memReadResp_payload_id = mshr_memReadResp_payload_id;
    assign mshr_vif.fill_en = mshr_fill_en;
    assign mshr_vif.fill_index = mshr_fill_index;
    assign mshr_vif.fill_way = mshr_fill_way;
    assign mshr_vif.fill_tag = mshr_fill_tag;
    assign mshr_vif.fill_dirty = mshr_fill_dirty;
    assign mshr_vif.fill_line = mshr_fill_line;
    assign mshr_vif.fillReady = mshr_fillReady;
    assign mshr_vif.replay_valid = mshr_replay_valid;
    assign mshr_vif.replay_ready = mshr_replay_ready;
    assign mshr_vif.replay_payload_rData = mshr_replay_payload_rData;
    assign mshr_vif.replay_payload_id = mshr_replay_payload_id;
    assign mshr_vif.replay_payload_isWrite = mshr_replay_payload_isWrite;
    assign mshr_vif.lockMask = mshr_lockMask;
    assign wbb_vif.reserve_en = wbb_reserve_en;
    assign wbb_vif.reserve_addr = wbb_reserve_addr;
    assign wbb_vif.push_en = wbb_push_en;
    assign wbb_vif.push_slot = wbb_push_slot;
    assign wbb_vif.push_line = wbb_push_line;
    assign wbb_vif.send_ready = wbb_send_ready;
    assign wbb_vif.memWriteResp_valid = wbb_memWriteResp_valid;
    assign wbb_vif.memWriteResp_payload_id = wbb_memWriteResp_payload_id;
    assign wbb_vif.q0Addr = wbb_q0Addr;
    assign wbb_vif.q1Addr = wbb_q1Addr;
    assign wbb_vif.reserveOk = wbb_reserveOk;
    assign wbb_vif.reserveSlot = wbb_reserveSlot;
    assign wbb_vif.send_valid = wbb_send_valid;
    assign wbb_vif.send_payload_addr = wbb_send_payload_addr;
    assign wbb_vif.send_payload_wData = wbb_send_payload_wData;
    assign wbb_vif.send_payload_id = wbb_send_payload_id;
    assign wbb_vif.memWriteResp_ready = wbb_memWriteResp_ready;
    assign wbb_vif.full = wbb_full;
    assign wbb_vif.q0Same = wbb_q0Same;
    assign wbb_vif.q1Same = wbb_q1Same;

    mshr_io_assertions mshr_sva(mshr_vif);
    wbb_io_assertions wbb_sva(
        .clk(clk),
        .rst_n(rst_n),
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
        uvm_config_db #(virtual mshr_interface)::set(null, "uvm_test_top.env", "mshr_vif", mshr_vif);
        uvm_config_db #(virtual wbb_interface)::set(null, "uvm_test_top.env", "wbb_vif", wbb_vif);
    end
endmodule

`ifndef DCACHE_PORT_STUB
bind DCache dcache_ip_bind u_dcache_ip_checks (
    .clk(clk),
    .rst_n(resetn),
    .mshr_alloc_en(UnitMshr.alloc_en),
    .mshr_alloc_tag(UnitMshr.alloc_tag),
    .mshr_alloc_index(UnitMshr.alloc_index),
    .mshr_alloc_way(UnitMshr.alloc_way),
    .mshr_alloc_isWrite(UnitMshr.alloc_isWrite),
    .mshr_alloc_wData(UnitMshr.alloc_wData),
    .mshr_alloc_wordOff(UnitMshr.alloc_wordOff),
    .mshr_alloc_respId(UnitMshr.alloc_respId),
    .mshr_alloc_wbSlot(UnitMshr.alloc_wbSlot),
    .mshr_alloc_hasWb(UnitMshr.alloc_hasWb),
    .mshr_merge_en(UnitMshr.merge_en),
    .mshr_merge_entry(UnitMshr.merge_entry),
    .mshr_merge_isWrite(UnitMshr.merge_isWrite),
    .mshr_merge_wData(UnitMshr.merge_wData),
    .mshr_merge_wordOff(UnitMshr.merge_wordOff),
    .mshr_merge_respId(UnitMshr.merge_respId),
    .mshr_q0_tag(UnitMshr.q0_tag),
    .mshr_q0_index(UnitMshr.q0_index),
    .mshr_q1_tag(UnitMshr.q1_tag),
    .mshr_q1_index(UnitMshr.q1_index),
    .mshr_m0_hit(UnitMshr.m0_hit),
    .mshr_m0_entry(UnitMshr.m0_entry),
    .mshr_m0_mergeable(UnitMshr.m0_mergeable),
    .mshr_m0_slotFree(UnitMshr.m0_slotFree),
    .mshr_m0_freeSlot(UnitMshr.m0_freeSlot),
    .mshr_m1_hit(UnitMshr.m1_hit),
    .mshr_m1_entry(UnitMshr.m1_entry),
    .mshr_m1_mergeable(UnitMshr.m1_mergeable),
    .mshr_m1_slotFree(UnitMshr.m1_slotFree),
    .mshr_m1_freeSlot(UnitMshr.m1_freeSlot),
    .mshr_hasFree(UnitMshr.hasFree),
    .mshr_freeEntry(UnitMshr.freeEntry),
    .mshr_memReadReq_valid(UnitMshr.memReadReq_valid),
    .mshr_memReadReq_ready(UnitMshr.memReadReq_ready),
    .mshr_memReadReq_payload_addr(UnitMshr.memReadReq_payload_addr),
    .mshr_memReadReq_payload_id(UnitMshr.memReadReq_payload_id),
    .mshr_memReadResp_valid(UnitMshr.memReadResp_valid),
    .mshr_memReadResp_ready(UnitMshr.memReadResp_ready),
    .mshr_memReadResp_payload_rData(UnitMshr.memReadResp_payload_rData),
    .mshr_memReadResp_payload_id(UnitMshr.memReadResp_payload_id),
    .mshr_fill_en(UnitMshr.fill_en),
    .mshr_fill_index(UnitMshr.fill_index),
    .mshr_fill_way(UnitMshr.fill_way),
    .mshr_fill_tag(UnitMshr.fill_tag),
    .mshr_fill_dirty(UnitMshr.fill_dirty),
    .mshr_fill_line(UnitMshr.fill_line),
    .mshr_fillReady(UnitMshr.fillReady),
    .mshr_replay_valid(UnitMshr.replay_valid),
    .mshr_replay_ready(UnitMshr.replay_ready),
    .mshr_replay_payload_rData(UnitMshr.replay_payload_rData),
    .mshr_replay_payload_id(UnitMshr.replay_payload_id),
    .mshr_replay_payload_isWrite(UnitMshr.replay_payload_isWrite),
    .mshr_lockMask(UnitMshr.lockMask),
    .wbb_reserve_en(UnitWbb.reserve_en),
    .wbb_reserve_addr(UnitWbb.reserve_addr),
    .wbb_push_en(UnitWbb.push_en),
    .wbb_push_slot(UnitWbb.push_slot),
    .wbb_push_line(UnitWbb.push_line),
    .wbb_send_ready(UnitWbb.send_ready),
    .wbb_memWriteResp_valid(UnitWbb.memWriteResp_valid),
    .wbb_memWriteResp_payload_id(UnitWbb.memWriteResp_payload_id),
    .wbb_q0Addr(UnitWbb.q0Addr),
    .wbb_q1Addr(UnitWbb.q1Addr),
    .wbb_reserveOk(UnitWbb.reserveOk),
    .wbb_reserveSlot(UnitWbb.reserveSlot),
    .wbb_send_valid(UnitWbb.send_valid),
    .wbb_send_payload_addr(UnitWbb.send_payload_addr),
    .wbb_send_payload_wData(UnitWbb.send_payload_wData),
    .wbb_send_payload_id(UnitWbb.send_payload_id),
    .wbb_memWriteResp_ready(UnitWbb.memWriteResp_ready),
    .wbb_full(UnitWbb.full),
    .wbb_q0Same(UnitWbb.q0Same),
    .wbb_q1Same(UnitWbb.q1Same)
);
`endif
