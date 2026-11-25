class dcache_filled_lock_test extends dcache_probe_test;
    `uvm_component_utils(dcache_filled_lock_test)
    function new(string name = "dcache_filled_lock_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 复用原正常接口激励与统一的外部/内部检查。
    virtual task run_sequence();
        dcache_filled_lock_sequence seq;
        seq = dcache_filled_lock_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
