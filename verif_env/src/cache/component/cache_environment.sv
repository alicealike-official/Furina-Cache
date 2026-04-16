// cache_environment.sv
class cache_environment extends uvm_env;
    cpu_cache_agent cpu_cache_agt;
    mem_cache_agent mem_cache_agt;
    
    `uvm_component_utils(cache_environment)
    
    function new(string name = "cache_environment", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

endclass


function void cache_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cpu_agt = cpu_cache_agent::type_id::create("cpu_agt", this);
    mem_cache_agt = mem_cache_agent::type_id::create("mem_cache_agt", this);
endfunction
    
function void cache_environment::connect_phase(uvm_phase phase);
    // 将sequencer通过config_db传递给virtual sequence
    uvm_config_db #(uvm_sequencer #(cpu_cache_transaction))::set(
        this, "*", "cpu_cache_sqr", cpu_agt.sequencer);
    uvm_config_db #(uvm_sequencer #(mem_cache_transaction))::set(
        this, "*", "mem_cache_sqr", mem_cache_agt.sequencer);
endfunction
