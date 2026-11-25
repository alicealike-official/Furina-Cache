class dcache_random_hotspot_test extends dcache_scenario_test;
    `uvm_component_utils(dcache_random_hotspot_test)
    function new(string name = "dcache_random_hotspot_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 每个profile独立运行和统计，避免混合总数代替单类场景。
    virtual task run_sequence();
        dcache_random_hotspot_sequence seq;
        seq = dcache_random_hotspot_sequence::type_id::create("seq");
        run_scenario(seq);
    endtask
endclass
