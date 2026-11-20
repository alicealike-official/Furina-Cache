class wbb_compare_item extends uvm_sequence_item;
    // Actual monitor sample and model expectations for the same clock edge.
    wbb_sample actual_sample;
    int expected_reserve_ok;
    int expected_reserve_slot;
    int expected_full;
    int expected_q0_same;
    int expected_q1_same;
    int expected_send_valid;
    int unsigned expected_send_addr;
    int unsigned expected_send_id;
    bit [LINE_WIDTH-1:0] expected_send_data;

    `uvm_object_utils(wbb_compare_item)

    function new(string name = "wbb_compare_item");
        super.new(name);
    endfunction

endclass
