class dcache_multi_stall_test extends dcache_probe_test;
    `uvm_component_utils(dcache_multi_stall_test)
    function new(string name = "dcache_multi_stall_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 通过CPU和内存正常握手建立边界重叠，统一检查目标是否实际命中。
    virtual task run_sequence();
        dcache_multi_stall_sequence seq;
        seq = dcache_multi_stall_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
