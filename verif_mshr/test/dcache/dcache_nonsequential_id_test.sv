class dcache_nonsequential_id_test extends dcache_probe_test;
    `uvm_component_utils(dcache_nonsequential_id_test)
    function new(string name = "dcache_nonsequential_id_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 启动定向sequence，统一核对外部结果及内部必要命中。
    virtual task run_sequence();
        dcache_nonsequential_id_sequence seq;
        seq = dcache_nonsequential_id_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
