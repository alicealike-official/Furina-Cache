class dcache_read_during_write_test extends dcache_probe_test;
    `uvm_component_utils(dcache_read_during_write_test)
    function new(string name = "dcache_read_during_write_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 复用公共启动、数据比较、排空及必要场景命中检查，test不生成随机激励。
    virtual task run_sequence();
        dcache_read_during_write_sequence seq;
        seq = dcache_read_during_write_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
