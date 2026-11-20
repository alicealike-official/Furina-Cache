interface mshr_interface(input logic clk, input logic rst_n);
    import mshr_params_pkg::*;

    // 分配一个新Entry并保存首个Slot。
    logic alloc_en;
    logic [TAG_WIDTH-1:0] alloc_tag;
    logic [INDEX_WIDTH-1:0] alloc_index;
    logic [WAY_WIDTH-1:0] alloc_way;
    logic alloc_isWrite;
    logic [DATA_WIDTH-1:0] alloc_wData;
    logic [WORD_OFF_WIDTH-1:0] alloc_wordOff;
    logic [CPU_ID_WIDTH-1:0] alloc_respId;
    logic [WBB_SLOT_WIDTH-1:0] alloc_wbSlot;
    logic alloc_hasWb;

    // 向已有Entry追加一个Slot。
    logic merge_en;
    logic [ENTRY_WIDTH-1:0] merge_entry;
    logic merge_isWrite;
    logic [DATA_WIDTH-1:0] merge_wData;
    logic [WORD_OFF_WIDTH-1:0] merge_wordOff;
    logic [CPU_ID_WIDTH-1:0] merge_respId;

    // 两路独立查询及可用资源。
    logic [TAG_WIDTH-1:0] q0_tag;
    logic [INDEX_WIDTH-1:0] q0_index;
    logic [TAG_WIDTH-1:0] q1_tag;
    logic [INDEX_WIDTH-1:0] q1_index;
    logic m0_hit;
    logic [ENTRY_WIDTH-1:0] m0_entry;
    logic m0_mergeable;
    logic m0_slotFree;
    logic [SLOT_WIDTH-1:0] m0_freeSlot;
    logic m1_hit;
    logic [ENTRY_WIDTH-1:0] m1_entry;
    logic m1_mergeable;
    logic m1_slotFree;
    logic [SLOT_WIDTH-1:0] m1_freeSlot;
    logic hasFree;
    logic [ENTRY_WIDTH-1:0] freeEntry;

    // DUT发出的整行内存读请求。
    logic memReadReq_valid;
    logic memReadReq_ready;
    logic [ADDR_WIDTH-1:0] memReadReq_payload_addr;
    logic [BUS_ID_WIDTH-1:0] memReadReq_payload_id;

    // 内存代理返回的整行读响应。
    logic memReadResp_valid;
    logic memReadResp_ready;
    logic [LINE_WIDTH-1:0] memReadResp_payload_rData;
    logic [BUS_ID_WIDTH-1:0] memReadResp_payload_id;

    // 填充目标和合并后的整行数据。
    logic fill_en;
    logic [INDEX_WIDTH-1:0] fill_index;
    logic [WAY_WIDTH-1:0] fill_way;
    logic [TAG_WIDTH-1:0] fill_tag;
    logic fill_dirty;
    logic [LINE_WIDTH-1:0] fill_line;
    logic fillReady;

    // 逐Slot重放及CPU响应身份。
    logic replay_valid;
    logic replay_ready;
    logic [DATA_WIDTH-1:0] replay_payload_rData;
    logic [CPU_ID_WIDTH-1:0] replay_payload_id;
    logic replay_payload_isWrite;

    // 所有set与way的占用锁。
    logic [LOCK_WIDTH-1:0] lockMask;

    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n;
        input alloc_en;
        input alloc_tag;
        input alloc_index;
        input alloc_way;
        input alloc_isWrite;
        input alloc_wData;
        input alloc_wordOff;
        input alloc_respId;
        input alloc_wbSlot;
        input alloc_hasWb;
        input merge_en;
        input merge_entry;
        input merge_isWrite;
        input merge_wData;
        input merge_wordOff;
        input merge_respId;
        input q0_tag;
        input q0_index;
        input q1_tag;
        input q1_index;
        input m0_hit;
        input m0_entry;
        input m0_mergeable;
        input m0_slotFree;
        input m0_freeSlot;
        input m1_hit;
        input m1_entry;
        input m1_mergeable;
        input m1_slotFree;
        input m1_freeSlot;
        input hasFree;
        input freeEntry;
        input memReadReq_valid;
        input memReadReq_ready;
        input memReadReq_payload_addr;
        input memReadReq_payload_id;
        input memReadResp_valid;
        input memReadResp_ready;
        input memReadResp_payload_rData;
        input memReadResp_payload_id;
        input fill_en;
        input fill_index;
        input fill_way;
        input fill_tag;
        input fill_dirty;
        input fill_line;
        input fillReady;
        input replay_valid;
        input replay_ready;
        input replay_payload_rData;
        input replay_payload_id;
        input replay_payload_isWrite;
        input lockMask;
    endclocking
endinterface
