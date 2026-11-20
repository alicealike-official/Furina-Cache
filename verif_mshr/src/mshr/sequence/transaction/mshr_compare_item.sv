class mshr_compare_item extends uvm_sequence_item;
    // 沿前IO采样及同一拍C++ MSHR预测。模型来源是RefModel/Cache/MSHR.hpp，
    // 预测由mshr_predictor经mshr_ref_step DPI产生；本对象自身不实现模型逻辑。
    mshr_sample actual_sample;
    int expected_hasFree;
    int expected_freeEntry;
    int expected_m0_hit;
    int expected_m0_entry;
    int expected_m0_mergeable;
    int expected_m0_slotFree;
    int expected_m0_freeSlot;
    int expected_m1_hit;
    int expected_m1_entry;
    int expected_m1_mergeable;
    int expected_m1_slotFree;
    int expected_m1_freeSlot;
    int expected_memReadReq_valid;
    int unsigned expected_memReadReq_payload_addr;
    int unsigned expected_memReadReq_payload_id;
    int expected_fill_en;
    int unsigned expected_fill_tag;
    int unsigned expected_fill_index;
    int unsigned expected_fill_way;
    int expected_fill_dirty;
    bit [LINE_WIDTH-1:0] expected_fill_line;
    int expected_replay_valid;
    int expected_replay_payload_isWrite;
    int unsigned expected_replay_payload_id;
    int unsigned expected_replay_payload_rData;

    `uvm_object_utils(mshr_compare_item)

    function new(string name = "mshr_compare_item");
        super.new(name);
    endfunction
endclass
