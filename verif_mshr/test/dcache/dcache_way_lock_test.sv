class dcache_way_lock_test extends dcache_probe_test;
    `uvm_component_utils(dcache_way_lock_test)
    function new(string name = "dcache_way_lock_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 启动正常接口激励并检查真实内部事件命中。
    virtual task run_sequence();
        dcache_way_lock_sequence seq;
        seq = dcache_way_lock_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
