class dcache_reset_test extends dcache_base_test;
    `uvm_component_utils(dcache_reset_test)
    function new(string name = "dcache_reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 连接环境拥有的时钟/复位和观察接口，数据与时序场景由sequence负责。
    virtual task run_sequence();
        dcache_reset_sequence seq;
        seq = create_reset_sequence();
        seq.clock_driver = env.clk_agent.driver;
        seq.vif = vif;
        seq.probe = env.probe_vif;
        seq.mshr_vif = env.mshr_vif;
        seq.wbb_vif = env.wbb_vif;
        seq.start(env.agent.sequencer);
    endtask
    // 子case只替换sequence，复位与探针依赖连接保持共用。
    virtual function dcache_reset_sequence create_reset_sequence();
        return dcache_reset_sequence::type_id::create("seq");
    endfunction
endclass
