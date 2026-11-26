class dcache_reset_active_test extends dcache_reset_test;
    `uvm_component_utils(dcache_reset_active_test)
    function new(string name = "dcache_reset_active_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.allow_reset_cancellation = 1;
        cfg.timeout_cycles = 20000;
    endfunction
    // 本地非空复位台架保持旧响应静默，不验证迟到响应处理。
    virtual function dcache_reset_sequence create_reset_sequence();
        return dcache_reset_active_sequence::type_id::create("seq");
    endfunction
endclass
