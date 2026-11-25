class dcache_entry_capacity_test extends dcache_scenario_test;
    `uvm_component_utils(dcache_entry_capacity_test)
    function new(string name = "dcache_entry_capacity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 启动容量场景并复用公共数据与命中检查。
    virtual task run_sequence();
        dcache_entry_capacity_sequence seq;
        seq = dcache_entry_capacity_sequence::type_id::create("seq");
        run_scenario(seq);
    endtask
endclass
