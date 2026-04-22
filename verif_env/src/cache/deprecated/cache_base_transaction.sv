class cache_base_transaction extends uvm_sequence_item;
    int trans_id;

    static int next_id = 0;
    `uvm_object_utils(cache_base_transaction)
    function new(string name = "cache_base_transaction");
        super.new();
        trans_id = next_id++;
    endfunction

endclass