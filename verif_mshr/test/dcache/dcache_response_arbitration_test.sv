class dcache_response_arbitration_test extends dcache_probe_test;
    `uvm_component_utils(dcache_response_arbitration_test)
    function new(string name = "dcache_response_arbitration_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 启动正常接口激励并检查真实内部事件命中。
    virtual task run_sequence();
        dcache_response_arbitration_sequence seq;
        seq = dcache_response_arbitration_sequence::type_id::create("seq");
        run_probe_scenario(seq);
    endtask
endclass
