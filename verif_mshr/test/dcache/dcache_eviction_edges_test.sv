class dcache_eviction_edges_test extends dcache_probe_test;
    `uvm_component_utils(dcache_eviction_edges_test)
    function new(string name = "dcache_eviction_edges_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 启动定向sequence，统一核对外部结果及内部必要命中。
    virtual task run_sequence();
        dcache_eviction_edges_sequence seq;
        seq = dcache_eviction_edges_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
