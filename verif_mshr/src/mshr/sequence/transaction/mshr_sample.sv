class mshr_sample extends uvm_sequence_item;
    // monitor在每个上升沿创建的完整IO快照；此对象不是上游请求。
    logic rst_n;

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

    `uvm_object_utils(mshr_sample)

    function new(string name = "mshr_sample");
        super.new(name);
    endfunction

endclass
