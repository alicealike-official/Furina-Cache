// ID_agent.sv
class ID_agent extends uvm_agent;
    instr_sequencer sqr;
    ID_driver drv;
    ID_monitor mon;
    instr_config instr_cfg;

    
    `uvm_component_utils(ID_agent)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(instr_config)::get(this, "", "instr_cfg", instr_cfg))
            `uvm_fatal("AGENT", "Failed to get instr_config")
        
        if (instr_cfg.is_active == UVM_ACTIVE) begin
            sqr = instr_sequencer::type_id::create("sqr", this);
            drv = ID_driver::type_id::create("drv", this);

        end
        
        mon = ID_monitor::type_id::create("mon", this);
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        if (instr_cfg.is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);  
        end
    endfunction
endclass
