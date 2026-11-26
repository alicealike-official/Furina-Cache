class wbb_reset_test extends wbb_base_test;
    `uvm_component_utils(wbb_reset_test)
    function new(string name = "wbb_reset_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 连接环境拥有的时钟/复位和观察接口，数据与时序场景由sequence负责。
    virtual task run_sequence();
        wbb_reset_sequence seq;
        seq = create_reset_sequence();
        seq.clock_driver = env.clk_agent.driver;
        seq.vif = vif;
        seq.obs = env.activity;
        seq.start(env.agent.sequencer);
    endtask
    // 子case只替换sequence类型，复位接口接入和启动逻辑保持共用。
    virtual function wbb_reset_sequence create_reset_sequence();
        return wbb_reset_sequence::type_id::create("seq");
    endfunction
endclass
