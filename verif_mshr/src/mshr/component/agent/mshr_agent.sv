class mshr_agent extends uvm_agent;
    mshr_driver driver;
    mshr_monitor monitor;
    mshr_sequencer sequencer;
    mshr_config cfg;

    `uvm_component_utils(mshr_agent)

    function new(string name = "mshr_agent",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
endclass

function void mshr_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null) begin
        `fatal("Environment must provide mshr_config", "MSHR_CONFIG")
    end
    is_active = cfg.is_active;
    monitor = mshr_monitor::type_id::create("monitor", this);
    if (is_active == UVM_ACTIVE) begin
        uvm_config_db #(mshr_config)::set(this, "driver", "mshr_config", cfg);
        uvm_config_db #(mshr_config)::set(this, "sequencer", "mshr_config", cfg);
        driver = mshr_driver::type_id::create("driver", this);
        sequencer = mshr_sequencer::type_id::create("sequencer", this);
    end
endfunction

function void mshr_agent::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (is_active == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
    end
endfunction
