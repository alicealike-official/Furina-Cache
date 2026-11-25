class dcache_random_test extends dcache_scenario_test;
    `uvm_component_utils(dcache_random_test)
    function new(string name = "dcache_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 子test只选择场景，配置/计数/错误报告复用公共工具。
    virtual task run_sequence();
        dcache_random_sequence seq;
        seq = dcache_random_sequence::type_id::create("seq");
        run_scenario(seq);
    endtask
endclass
