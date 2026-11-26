class wbb_reset_active_test extends wbb_reset_test;
    `uvm_component_utils(wbb_reset_active_test)
    function new(string name = "wbb_reset_active_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.allow_reset_cancellation = 1;
    endfunction
    // 本case取消本地义务；已发送/等响应场景保持外部源静默，不验迟到返回。
    virtual function wbb_reset_sequence create_reset_sequence();
        return wbb_reset_active_sequence::type_id::create("seq");
    endfunction
endclass
