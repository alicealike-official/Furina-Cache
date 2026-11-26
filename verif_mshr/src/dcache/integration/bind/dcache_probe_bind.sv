// 所有DE层级映射集中在本文件。只连接实例端口及架构命名的顶层提交信号，不驱动DUT。
// 修改RTL命名时只更新下面bind接线；端口缺失会编译失败，禁止补常量蒙混通过。
module dcache_probe_bind(
    input wire clk,
    input wire rst_n,
    input wire cache_r2_en,
    input wire [4:0] cache_r2_index,
    input wire [1:0] cache_r2_way,
    input wire [511:0] cache_r2_line,
    input wire cache_clr_en,
    input wire [4:0] cache_clr_index,
    input wire [1:0] cache_clr_way,
    input wire cache_w2_en,
    input wire [4:0] cache_w2_index,
    input wire [1:0] cache_w2_way,
    input wire [20:0] cache_w2_tag,
    input wire cache_w2_dirty,
    input wire [511:0] cache_w2_line,
    input wire rd_io_push_valid,
    input wire rd_io_push_ready,
    input wire [4:0] rd_io_push_payload_id,
    input wire rd_io_pop_valid,
    input wire rd_io_pop_ready,
    input wire [4:0] rd_io_pop_payload_id,
    input wire [2:0] rd_io_occupancy,
    input wire wr_io_push_valid,
    input wire wr_io_push_ready,
    input wire [4:0] wr_io_push_payload_id,
    input wire wr_io_pop_valid,
    input wire wr_io_pop_ready,
    input wire [4:0] wr_io_pop_payload_id,
    input wire [2:0] wr_io_occupancy,
    input wire [31:0] rd_io_push_payload_rData,
    input wire [31:0] rd_io_pop_payload_rData,
    input wire hitRead,
    input wire hitWrite,
    input wire [31:0] hitReadData,
    input wire [1:0] hitWay,
    input wire [4:0] s1Index,
    input wire [4:0] s1Id,
    input wire s1Valid,
    input wire s2Stuck,
    input wire [127:0] cache_valid_map,
    input wire [127:0] cache_dirty_map,
    input wire [2687:0] cache_tag_map,
    input wire commit,
    input wire cache_r1_en,
    input wire [4:0] cache_r1_index,
    input wire [3:0] cache_r1_wordOff,
    input wire cache_w1_en,
    input wire [4:0] cache_w1_index,
    input wire [1:0] cache_w1_way,
    input wire [3:0] cache_w1_wordOff,
    input wire [31:0] cache_w1_data,
    input wire [4:0] cache_inspect_index,
    input wire [3:0] cache_inspect_valid,
    input wire [3:0] cache_inspect_dirty,
    input wire [20:0] cache_r1_tag_0,
    input wire cache_r1_valid_0,
    input wire cache_r1_dirty_0,
    input wire [31:0] cache_r1_data_0,
    input wire [20:0] cache_r1_tag_1,
    input wire cache_r1_valid_1,
    input wire cache_r1_dirty_1,
    input wire [31:0] cache_r1_data_1,
    input wire [20:0] cache_r1_tag_2,
    input wire cache_r1_valid_2,
    input wire cache_r1_dirty_2,
    input wire [31:0] cache_r1_data_2,
    input wire [20:0] cache_r1_tag_3,
    input wire cache_r1_valid_3,
    input wire cache_r1_dirty_3,
    input wire [31:0] cache_r1_data_3,
    input wire [20:0] s1Tag,
    input wire [3:0] s1WordOff,
    input wire s1WrEn,
    input wire [31:0] s1WData,
    input wire p1Valid,
    input wire [20:0] p1Tag,
    input wire [4:0] p1Index,
    input wire [1:0] p1Way,
    input wire [3:0] p1WordOff,
    input wire [31:0] p1Data,
    input wire bypass,
    input wire canMerge0,
    input wire canMerge1,
    input wire hasVictim,
    input wire respFullAny,
    input wire evictDirty,
    input wire [1:0] policyWay,
    input wire [255:0] fifo_order
);
    import uvm_pkg::*;
    dcache_probe_interface probe(clk, rst_n);
    assign probe.connected = 1'b1;
    assign probe.cache_r2_en = cache_r2_en;
    assign probe.cache_r2_index = cache_r2_index;
    assign probe.cache_r2_way = cache_r2_way;
    assign probe.cache_r2_line = cache_r2_line;
    assign probe.cache_clr_en = cache_clr_en;
    assign probe.cache_clr_index = cache_clr_index;
    assign probe.cache_clr_way = cache_clr_way;
    assign probe.cache_w2_en = cache_w2_en;
    assign probe.cache_w2_index = cache_w2_index;
    assign probe.cache_w2_way = cache_w2_way;
    assign probe.cache_w2_tag = cache_w2_tag;
    assign probe.cache_w2_dirty = cache_w2_dirty;
    assign probe.cache_w2_line = cache_w2_line;
    assign probe.rd_io_push_valid = rd_io_push_valid;
    assign probe.rd_io_push_ready = rd_io_push_ready;
    assign probe.rd_io_push_payload_id = rd_io_push_payload_id;
    assign probe.rd_io_pop_valid = rd_io_pop_valid;
    assign probe.rd_io_pop_ready = rd_io_pop_ready;
    assign probe.rd_io_pop_payload_id = rd_io_pop_payload_id;
    assign probe.rd_io_occupancy = rd_io_occupancy;
    assign probe.wr_io_push_valid = wr_io_push_valid;
    assign probe.wr_io_push_ready = wr_io_push_ready;
    assign probe.wr_io_push_payload_id = wr_io_push_payload_id;
    assign probe.wr_io_pop_valid = wr_io_pop_valid;
    assign probe.wr_io_pop_ready = wr_io_pop_ready;
    assign probe.wr_io_pop_payload_id = wr_io_pop_payload_id;
    assign probe.wr_io_occupancy = wr_io_occupancy;
    assign probe.rd_io_push_payload_rData = rd_io_push_payload_rData;
    assign probe.rd_io_pop_payload_rData = rd_io_pop_payload_rData;
    assign probe.hitRead = hitRead;
    assign probe.hitWrite = hitWrite;
    assign probe.hitReadData = hitReadData;
    assign probe.hitWay = hitWay;
    assign probe.s1Index = s1Index;
    assign probe.s1Id = s1Id;
    assign probe.s1Valid = s1Valid;
    assign probe.s2Stuck = s2Stuck;
    assign probe.commit = commit;
    assign probe.cache_r1_en = cache_r1_en;
    assign probe.cache_r1_index = cache_r1_index;
    assign probe.cache_r1_wordOff = cache_r1_wordOff;
    assign probe.cache_w1_en = cache_w1_en;
    assign probe.cache_w1_index = cache_w1_index;
    assign probe.cache_w1_way = cache_w1_way;
    assign probe.cache_w1_wordOff = cache_w1_wordOff;
    assign probe.cache_w1_data = cache_w1_data;
    assign probe.cache_inspect_index = cache_inspect_index;
    assign probe.cache_inspect_valid = cache_inspect_valid;
    assign probe.cache_inspect_dirty = cache_inspect_dirty;
    assign probe.cache_r1_tag_0 = cache_r1_tag_0;
    assign probe.cache_r1_valid_0 = cache_r1_valid_0;
    assign probe.cache_r1_dirty_0 = cache_r1_dirty_0;
    assign probe.cache_r1_data_0 = cache_r1_data_0;
    assign probe.cache_r1_tag_1 = cache_r1_tag_1;
    assign probe.cache_r1_valid_1 = cache_r1_valid_1;
    assign probe.cache_r1_dirty_1 = cache_r1_dirty_1;
    assign probe.cache_r1_data_1 = cache_r1_data_1;
    assign probe.cache_r1_tag_2 = cache_r1_tag_2;
    assign probe.cache_r1_valid_2 = cache_r1_valid_2;
    assign probe.cache_r1_dirty_2 = cache_r1_dirty_2;
    assign probe.cache_r1_data_2 = cache_r1_data_2;
    assign probe.cache_r1_tag_3 = cache_r1_tag_3;
    assign probe.cache_r1_valid_3 = cache_r1_valid_3;
    assign probe.cache_r1_dirty_3 = cache_r1_dirty_3;
    assign probe.cache_r1_data_3 = cache_r1_data_3;
    assign probe.s1Tag = s1Tag;
    assign probe.s1WordOff = s1WordOff;
    assign probe.s1WrEn = s1WrEn;
    assign probe.s1WData = s1WData;
    assign probe.p1Valid = p1Valid;
    assign probe.p1Tag = p1Tag;
    assign probe.p1Index = p1Index;
    assign probe.p1Way = p1Way;
    assign probe.p1WordOff = p1WordOff;
    assign probe.p1Data = p1Data;
    assign probe.bypass = bypass;
    assign probe.canMerge0 = canMerge0;
    assign probe.canMerge1 = canMerge1;
    assign probe.hasVictim = hasVictim;
    assign probe.respFullAny = respFullAny;
    assign probe.evictDirty = evictDirty;
    assign probe.policyWay = policyWay;
    assign probe.fifo_order = fifo_order;
    assign probe.cache_valid_map = cache_valid_map;
    assign probe.cache_dirty_map = cache_dirty_map;
    assign probe.cache_tag_map = cache_tag_map;
    initial begin
        uvm_config_db #(virtual dcache_probe_interface)::set(null, "uvm_test_top.env", "dcache_probe_vif", probe);
    end
endmodule

`ifndef DCACHE_PORT_STUB
bind DCache dcache_probe_bind u_dcache_probe (
    .clk(clk),
    .rst_n(resetn),
    .cache_r2_en(UnitCache.r2_en),
    .cache_r2_index(UnitCache.r2_index),
    .cache_r2_way(UnitCache.r2_way),
    .cache_r2_line(UnitCache.r2_line),
    .cache_clr_en(UnitCache.clr_en),
    .cache_clr_index(UnitCache.clr_index),
    .cache_clr_way(UnitCache.clr_way),
    .cache_w2_en(UnitCache.w2_en),
    .cache_w2_index(UnitCache.w2_index),
    .cache_w2_way(UnitCache.w2_way),
    .cache_w2_tag(UnitCache.w2_tag),
    .cache_w2_dirty(UnitCache.w2_dirty),
    .cache_w2_line(UnitCache.w2_line),
    .rd_io_push_valid(UnitRdFifo.io_push_valid),
    .rd_io_push_ready(UnitRdFifo.io_push_ready),
    .rd_io_push_payload_id(UnitRdFifo.io_push_payload_id),
    .rd_io_pop_valid(UnitRdFifo.io_pop_valid),
    .rd_io_pop_ready(UnitRdFifo.io_pop_ready),
    .rd_io_pop_payload_id(UnitRdFifo.io_pop_payload_id),
    .rd_io_occupancy(UnitRdFifo.io_occupancy),
    .wr_io_push_valid(UnitWrFifo.io_push_valid),
    .wr_io_push_ready(UnitWrFifo.io_push_ready),
    .wr_io_push_payload_id(UnitWrFifo.io_push_payload_id),
    .wr_io_pop_valid(UnitWrFifo.io_pop_valid),
    .wr_io_pop_ready(UnitWrFifo.io_pop_ready),
    .wr_io_pop_payload_id(UnitWrFifo.io_pop_payload_id),
    .wr_io_occupancy(UnitWrFifo.io_occupancy),
    .rd_io_push_payload_rData(UnitRdFifo.io_push_payload_rData),
    .rd_io_pop_payload_rData(UnitRdFifo.io_pop_payload_rData),
    .hitRead(hitRead),
    .hitWrite(hitWrite),
    .hitReadData(hitReadData),
    .hitWay(hitWay),
    .s1Index(s1Index),
    .s1Id(s1Id),
    .s1Valid(s1Valid),
    .s2Stuck(s2Stuck),
    .cache_valid_map({UnitCache.validBits_31_3, UnitCache.validBits_31_2, UnitCache.validBits_31_1, UnitCache.validBits_31_0, UnitCache.validBits_30_3, UnitCache.validBits_30_2, UnitCache.validBits_30_1, UnitCache.validBits_30_0, UnitCache.validBits_29_3, UnitCache.validBits_29_2, UnitCache.validBits_29_1, UnitCache.validBits_29_0, UnitCache.validBits_28_3, UnitCache.validBits_28_2, UnitCache.validBits_28_1, UnitCache.validBits_28_0, UnitCache.validBits_27_3, UnitCache.validBits_27_2, UnitCache.validBits_27_1, UnitCache.validBits_27_0, UnitCache.validBits_26_3, UnitCache.validBits_26_2, UnitCache.validBits_26_1, UnitCache.validBits_26_0, UnitCache.validBits_25_3, UnitCache.validBits_25_2, UnitCache.validBits_25_1, UnitCache.validBits_25_0, UnitCache.validBits_24_3, UnitCache.validBits_24_2, UnitCache.validBits_24_1, UnitCache.validBits_24_0, UnitCache.validBits_23_3, UnitCache.validBits_23_2, UnitCache.validBits_23_1, UnitCache.validBits_23_0, UnitCache.validBits_22_3, UnitCache.validBits_22_2, UnitCache.validBits_22_1, UnitCache.validBits_22_0, UnitCache.validBits_21_3, UnitCache.validBits_21_2, UnitCache.validBits_21_1, UnitCache.validBits_21_0, UnitCache.validBits_20_3, UnitCache.validBits_20_2, UnitCache.validBits_20_1, UnitCache.validBits_20_0, UnitCache.validBits_19_3, UnitCache.validBits_19_2, UnitCache.validBits_19_1, UnitCache.validBits_19_0, UnitCache.validBits_18_3, UnitCache.validBits_18_2, UnitCache.validBits_18_1, UnitCache.validBits_18_0, UnitCache.validBits_17_3, UnitCache.validBits_17_2, UnitCache.validBits_17_1, UnitCache.validBits_17_0, UnitCache.validBits_16_3, UnitCache.validBits_16_2, UnitCache.validBits_16_1, UnitCache.validBits_16_0, UnitCache.validBits_15_3, UnitCache.validBits_15_2, UnitCache.validBits_15_1, UnitCache.validBits_15_0, UnitCache.validBits_14_3, UnitCache.validBits_14_2, UnitCache.validBits_14_1, UnitCache.validBits_14_0, UnitCache.validBits_13_3, UnitCache.validBits_13_2, UnitCache.validBits_13_1, UnitCache.validBits_13_0, UnitCache.validBits_12_3, UnitCache.validBits_12_2, UnitCache.validBits_12_1, UnitCache.validBits_12_0, UnitCache.validBits_11_3, UnitCache.validBits_11_2, UnitCache.validBits_11_1, UnitCache.validBits_11_0, UnitCache.validBits_10_3, UnitCache.validBits_10_2, UnitCache.validBits_10_1, UnitCache.validBits_10_0, UnitCache.validBits_9_3, UnitCache.validBits_9_2, UnitCache.validBits_9_1, UnitCache.validBits_9_0, UnitCache.validBits_8_3, UnitCache.validBits_8_2, UnitCache.validBits_8_1, UnitCache.validBits_8_0, UnitCache.validBits_7_3, UnitCache.validBits_7_2, UnitCache.validBits_7_1, UnitCache.validBits_7_0, UnitCache.validBits_6_3, UnitCache.validBits_6_2, UnitCache.validBits_6_1, UnitCache.validBits_6_0, UnitCache.validBits_5_3, UnitCache.validBits_5_2, UnitCache.validBits_5_1, UnitCache.validBits_5_0, UnitCache.validBits_4_3, UnitCache.validBits_4_2, UnitCache.validBits_4_1, UnitCache.validBits_4_0, UnitCache.validBits_3_3, UnitCache.validBits_3_2, UnitCache.validBits_3_1, UnitCache.validBits_3_0, UnitCache.validBits_2_3, UnitCache.validBits_2_2, UnitCache.validBits_2_1, UnitCache.validBits_2_0, UnitCache.validBits_1_3, UnitCache.validBits_1_2, UnitCache.validBits_1_1, UnitCache.validBits_1_0, UnitCache.validBits_0_3, UnitCache.validBits_0_2, UnitCache.validBits_0_1, UnitCache.validBits_0_0}),
    .cache_dirty_map({UnitCache.dirtyBits_31_3, UnitCache.dirtyBits_31_2, UnitCache.dirtyBits_31_1, UnitCache.dirtyBits_31_0, UnitCache.dirtyBits_30_3, UnitCache.dirtyBits_30_2, UnitCache.dirtyBits_30_1, UnitCache.dirtyBits_30_0, UnitCache.dirtyBits_29_3, UnitCache.dirtyBits_29_2, UnitCache.dirtyBits_29_1, UnitCache.dirtyBits_29_0, UnitCache.dirtyBits_28_3, UnitCache.dirtyBits_28_2, UnitCache.dirtyBits_28_1, UnitCache.dirtyBits_28_0, UnitCache.dirtyBits_27_3, UnitCache.dirtyBits_27_2, UnitCache.dirtyBits_27_1, UnitCache.dirtyBits_27_0, UnitCache.dirtyBits_26_3, UnitCache.dirtyBits_26_2, UnitCache.dirtyBits_26_1, UnitCache.dirtyBits_26_0, UnitCache.dirtyBits_25_3, UnitCache.dirtyBits_25_2, UnitCache.dirtyBits_25_1, UnitCache.dirtyBits_25_0, UnitCache.dirtyBits_24_3, UnitCache.dirtyBits_24_2, UnitCache.dirtyBits_24_1, UnitCache.dirtyBits_24_0, UnitCache.dirtyBits_23_3, UnitCache.dirtyBits_23_2, UnitCache.dirtyBits_23_1, UnitCache.dirtyBits_23_0, UnitCache.dirtyBits_22_3, UnitCache.dirtyBits_22_2, UnitCache.dirtyBits_22_1, UnitCache.dirtyBits_22_0, UnitCache.dirtyBits_21_3, UnitCache.dirtyBits_21_2, UnitCache.dirtyBits_21_1, UnitCache.dirtyBits_21_0, UnitCache.dirtyBits_20_3, UnitCache.dirtyBits_20_2, UnitCache.dirtyBits_20_1, UnitCache.dirtyBits_20_0, UnitCache.dirtyBits_19_3, UnitCache.dirtyBits_19_2, UnitCache.dirtyBits_19_1, UnitCache.dirtyBits_19_0, UnitCache.dirtyBits_18_3, UnitCache.dirtyBits_18_2, UnitCache.dirtyBits_18_1, UnitCache.dirtyBits_18_0, UnitCache.dirtyBits_17_3, UnitCache.dirtyBits_17_2, UnitCache.dirtyBits_17_1, UnitCache.dirtyBits_17_0, UnitCache.dirtyBits_16_3, UnitCache.dirtyBits_16_2, UnitCache.dirtyBits_16_1, UnitCache.dirtyBits_16_0, UnitCache.dirtyBits_15_3, UnitCache.dirtyBits_15_2, UnitCache.dirtyBits_15_1, UnitCache.dirtyBits_15_0, UnitCache.dirtyBits_14_3, UnitCache.dirtyBits_14_2, UnitCache.dirtyBits_14_1, UnitCache.dirtyBits_14_0, UnitCache.dirtyBits_13_3, UnitCache.dirtyBits_13_2, UnitCache.dirtyBits_13_1, UnitCache.dirtyBits_13_0, UnitCache.dirtyBits_12_3, UnitCache.dirtyBits_12_2, UnitCache.dirtyBits_12_1, UnitCache.dirtyBits_12_0, UnitCache.dirtyBits_11_3, UnitCache.dirtyBits_11_2, UnitCache.dirtyBits_11_1, UnitCache.dirtyBits_11_0, UnitCache.dirtyBits_10_3, UnitCache.dirtyBits_10_2, UnitCache.dirtyBits_10_1, UnitCache.dirtyBits_10_0, UnitCache.dirtyBits_9_3, UnitCache.dirtyBits_9_2, UnitCache.dirtyBits_9_1, UnitCache.dirtyBits_9_0, UnitCache.dirtyBits_8_3, UnitCache.dirtyBits_8_2, UnitCache.dirtyBits_8_1, UnitCache.dirtyBits_8_0, UnitCache.dirtyBits_7_3, UnitCache.dirtyBits_7_2, UnitCache.dirtyBits_7_1, UnitCache.dirtyBits_7_0, UnitCache.dirtyBits_6_3, UnitCache.dirtyBits_6_2, UnitCache.dirtyBits_6_1, UnitCache.dirtyBits_6_0, UnitCache.dirtyBits_5_3, UnitCache.dirtyBits_5_2, UnitCache.dirtyBits_5_1, UnitCache.dirtyBits_5_0, UnitCache.dirtyBits_4_3, UnitCache.dirtyBits_4_2, UnitCache.dirtyBits_4_1, UnitCache.dirtyBits_4_0, UnitCache.dirtyBits_3_3, UnitCache.dirtyBits_3_2, UnitCache.dirtyBits_3_1, UnitCache.dirtyBits_3_0, UnitCache.dirtyBits_2_3, UnitCache.dirtyBits_2_2, UnitCache.dirtyBits_2_1, UnitCache.dirtyBits_2_0, UnitCache.dirtyBits_1_3, UnitCache.dirtyBits_1_2, UnitCache.dirtyBits_1_1, UnitCache.dirtyBits_1_0, UnitCache.dirtyBits_0_3, UnitCache.dirtyBits_0_2, UnitCache.dirtyBits_0_1, UnitCache.dirtyBits_0_0}),
    .cache_tag_map({UnitCache.tagMems_3[31], UnitCache.tagMems_2[31], UnitCache.tagMems_1[31], UnitCache.tagMems_0[31], UnitCache.tagMems_3[30], UnitCache.tagMems_2[30], UnitCache.tagMems_1[30], UnitCache.tagMems_0[30], UnitCache.tagMems_3[29], UnitCache.tagMems_2[29], UnitCache.tagMems_1[29], UnitCache.tagMems_0[29], UnitCache.tagMems_3[28], UnitCache.tagMems_2[28], UnitCache.tagMems_1[28], UnitCache.tagMems_0[28], UnitCache.tagMems_3[27], UnitCache.tagMems_2[27], UnitCache.tagMems_1[27], UnitCache.tagMems_0[27], UnitCache.tagMems_3[26], UnitCache.tagMems_2[26], UnitCache.tagMems_1[26], UnitCache.tagMems_0[26], UnitCache.tagMems_3[25], UnitCache.tagMems_2[25], UnitCache.tagMems_1[25], UnitCache.tagMems_0[25], UnitCache.tagMems_3[24], UnitCache.tagMems_2[24], UnitCache.tagMems_1[24], UnitCache.tagMems_0[24], UnitCache.tagMems_3[23], UnitCache.tagMems_2[23], UnitCache.tagMems_1[23], UnitCache.tagMems_0[23], UnitCache.tagMems_3[22], UnitCache.tagMems_2[22], UnitCache.tagMems_1[22], UnitCache.tagMems_0[22], UnitCache.tagMems_3[21], UnitCache.tagMems_2[21], UnitCache.tagMems_1[21], UnitCache.tagMems_0[21], UnitCache.tagMems_3[20], UnitCache.tagMems_2[20], UnitCache.tagMems_1[20], UnitCache.tagMems_0[20], UnitCache.tagMems_3[19], UnitCache.tagMems_2[19], UnitCache.tagMems_1[19], UnitCache.tagMems_0[19], UnitCache.tagMems_3[18], UnitCache.tagMems_2[18], UnitCache.tagMems_1[18], UnitCache.tagMems_0[18], UnitCache.tagMems_3[17], UnitCache.tagMems_2[17], UnitCache.tagMems_1[17], UnitCache.tagMems_0[17], UnitCache.tagMems_3[16], UnitCache.tagMems_2[16], UnitCache.tagMems_1[16], UnitCache.tagMems_0[16], UnitCache.tagMems_3[15], UnitCache.tagMems_2[15], UnitCache.tagMems_1[15], UnitCache.tagMems_0[15], UnitCache.tagMems_3[14], UnitCache.tagMems_2[14], UnitCache.tagMems_1[14], UnitCache.tagMems_0[14], UnitCache.tagMems_3[13], UnitCache.tagMems_2[13], UnitCache.tagMems_1[13], UnitCache.tagMems_0[13], UnitCache.tagMems_3[12], UnitCache.tagMems_2[12], UnitCache.tagMems_1[12], UnitCache.tagMems_0[12], UnitCache.tagMems_3[11], UnitCache.tagMems_2[11], UnitCache.tagMems_1[11], UnitCache.tagMems_0[11], UnitCache.tagMems_3[10], UnitCache.tagMems_2[10], UnitCache.tagMems_1[10], UnitCache.tagMems_0[10], UnitCache.tagMems_3[9], UnitCache.tagMems_2[9], UnitCache.tagMems_1[9], UnitCache.tagMems_0[9], UnitCache.tagMems_3[8], UnitCache.tagMems_2[8], UnitCache.tagMems_1[8], UnitCache.tagMems_0[8], UnitCache.tagMems_3[7], UnitCache.tagMems_2[7], UnitCache.tagMems_1[7], UnitCache.tagMems_0[7], UnitCache.tagMems_3[6], UnitCache.tagMems_2[6], UnitCache.tagMems_1[6], UnitCache.tagMems_0[6], UnitCache.tagMems_3[5], UnitCache.tagMems_2[5], UnitCache.tagMems_1[5], UnitCache.tagMems_0[5], UnitCache.tagMems_3[4], UnitCache.tagMems_2[4], UnitCache.tagMems_1[4], UnitCache.tagMems_0[4], UnitCache.tagMems_3[3], UnitCache.tagMems_2[3], UnitCache.tagMems_1[3], UnitCache.tagMems_0[3], UnitCache.tagMems_3[2], UnitCache.tagMems_2[2], UnitCache.tagMems_1[2], UnitCache.tagMems_0[2], UnitCache.tagMems_3[1], UnitCache.tagMems_2[1], UnitCache.tagMems_1[1], UnitCache.tagMems_0[1], UnitCache.tagMems_3[0], UnitCache.tagMems_2[0], UnitCache.tagMems_1[0], UnitCache.tagMems_0[0]}),
    .commit(commit),
    .cache_r1_en(UnitCache.r1_en),
    .cache_r1_index(UnitCache.r1_index),
    .cache_r1_wordOff(UnitCache.r1_wordOff),
    .cache_w1_en(UnitCache.w1_en),
    .cache_w1_index(UnitCache.w1_index),
    .cache_w1_way(UnitCache.w1_way),
    .cache_w1_wordOff(UnitCache.w1_wordOff),
    .cache_w1_data(UnitCache.w1_data),
    .cache_inspect_index(UnitCache.inspect_index),
    .cache_inspect_valid(UnitCache.inspect_valid),
    .cache_inspect_dirty(UnitCache.inspect_dirty),
    .cache_r1_tag_0(UnitCache.r1_tag_0),
    .cache_r1_valid_0(UnitCache.r1_valid_0),
    .cache_r1_dirty_0(UnitCache.r1_dirty_0),
    .cache_r1_data_0(UnitCache.r1_data_0),
    .cache_r1_tag_1(UnitCache.r1_tag_1),
    .cache_r1_valid_1(UnitCache.r1_valid_1),
    .cache_r1_dirty_1(UnitCache.r1_dirty_1),
    .cache_r1_data_1(UnitCache.r1_data_1),
    .cache_r1_tag_2(UnitCache.r1_tag_2),
    .cache_r1_valid_2(UnitCache.r1_valid_2),
    .cache_r1_dirty_2(UnitCache.r1_dirty_2),
    .cache_r1_data_2(UnitCache.r1_data_2),
    .cache_r1_tag_3(UnitCache.r1_tag_3),
    .cache_r1_valid_3(UnitCache.r1_valid_3),
    .cache_r1_dirty_3(UnitCache.r1_dirty_3),
    .cache_r1_data_3(UnitCache.r1_data_3),
    .s1Tag(s1Tag),
    .s1WordOff(s1WordOff),
    .s1WrEn(s1WrEn),
    .s1WData(s1WData),
    .p1Valid(p1Valid),
    .p1Tag(p1Tag),
    .p1Index(p1Index),
    .p1Way(p1Way),
    .p1WordOff(p1WordOff),
    .p1Data(p1Data),
    .bypass(bypass),
    .canMerge0(canMerge0),
    .canMerge1(canMerge1),
    .hasVictim(hasVictim),
    .respFullAny(respFullAny),
    .evictDirty(evictDirty),
    .policyWay(policyWay),
    .fifo_order({policy_order_31_3, policy_order_31_2, policy_order_31_1, policy_order_31_0, policy_order_30_3, policy_order_30_2, policy_order_30_1, policy_order_30_0, policy_order_29_3, policy_order_29_2, policy_order_29_1, policy_order_29_0, policy_order_28_3, policy_order_28_2, policy_order_28_1, policy_order_28_0, policy_order_27_3, policy_order_27_2, policy_order_27_1, policy_order_27_0, policy_order_26_3, policy_order_26_2, policy_order_26_1, policy_order_26_0, policy_order_25_3, policy_order_25_2, policy_order_25_1, policy_order_25_0, policy_order_24_3, policy_order_24_2, policy_order_24_1, policy_order_24_0, policy_order_23_3, policy_order_23_2, policy_order_23_1, policy_order_23_0, policy_order_22_3, policy_order_22_2, policy_order_22_1, policy_order_22_0, policy_order_21_3, policy_order_21_2, policy_order_21_1, policy_order_21_0, policy_order_20_3, policy_order_20_2, policy_order_20_1, policy_order_20_0, policy_order_19_3, policy_order_19_2, policy_order_19_1, policy_order_19_0, policy_order_18_3, policy_order_18_2, policy_order_18_1, policy_order_18_0, policy_order_17_3, policy_order_17_2, policy_order_17_1, policy_order_17_0, policy_order_16_3, policy_order_16_2, policy_order_16_1, policy_order_16_0, policy_order_15_3, policy_order_15_2, policy_order_15_1, policy_order_15_0, policy_order_14_3, policy_order_14_2, policy_order_14_1, policy_order_14_0, policy_order_13_3, policy_order_13_2, policy_order_13_1, policy_order_13_0, policy_order_12_3, policy_order_12_2, policy_order_12_1, policy_order_12_0, policy_order_11_3, policy_order_11_2, policy_order_11_1, policy_order_11_0, policy_order_10_3, policy_order_10_2, policy_order_10_1, policy_order_10_0, policy_order_9_3, policy_order_9_2, policy_order_9_1, policy_order_9_0, policy_order_8_3, policy_order_8_2, policy_order_8_1, policy_order_8_0, policy_order_7_3, policy_order_7_2, policy_order_7_1, policy_order_7_0, policy_order_6_3, policy_order_6_2, policy_order_6_1, policy_order_6_0, policy_order_5_3, policy_order_5_2, policy_order_5_1, policy_order_5_0, policy_order_4_3, policy_order_4_2, policy_order_4_1, policy_order_4_0, policy_order_3_3, policy_order_3_2, policy_order_3_1, policy_order_3_0, policy_order_2_3, policy_order_2_2, policy_order_2_1, policy_order_2_0, policy_order_1_3, policy_order_1_2, policy_order_1_1, policy_order_1_0, policy_order_0_3, policy_order_0_2, policy_order_0_1, policy_order_0_0})
);
`endif
