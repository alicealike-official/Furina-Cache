class wbb_config extends uvm_object;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    int unsigned timeout_cycles = 2000;
    int unsigned reserve_timeout_cycles = 1000;
    int unsigned mem_page_size = 4096;
    realtime mem_write_latency_ns = 10.0;
    int unsigned mem_max_pending = WBB_ENTRIES;
    `uvm_object_utils(wbb_config)

    function new(string name = "wbb_config");
        super.new(name);
    endfunction

endclass
