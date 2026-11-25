class dcache_agent extends uvm_agent;
    dcache_monitor monitor;
    dcache_driver driver;
    dcache_sequencer sequencer;
    dcache_config cfg;
    `uvm_component_utils(dcache_agent)
    function new(string name = "dcache_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】active/passive配置必须来自上层。
        if (!uvm_config_db #(dcache_config)::get(this, "", "dcache_config", cfg)) begin
            `fatal("Agent configuration missing", "DCACHE_CONFIG")
        end
        monitor = dcache_monitor::type_id::create("monitor", this);
        if (cfg.is_active == UVM_ACTIVE) begin
            driver = dcache_driver::type_id::create("driver", this);
            sequencer = dcache_sequencer::type_id::create("sequencer", this);
        end
    endfunction
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (driver != null) driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
