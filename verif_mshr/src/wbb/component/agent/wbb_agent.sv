class wbb_agent extends uvm_agent;
    wbb_driver driver;
    wbb_monitor monitor;
    wbb_sequencer sequencer;
    wbb_config cfg;

    `uvm_component_utils(wbb_agent)

    function new(string name = "wbb_agent",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
endclass

function void wbb_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg)) begin
        `fatal("wbb_config not found")
    end
    is_active = cfg.is_active;
    monitor = wbb_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
        driver = wbb_driver::type_id::create("driver", this);
        sequencer = wbb_sequencer::type_id::create("sequencer", this);
    end
endfunction

function void wbb_agent::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (is_active == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
    end
endfunction
