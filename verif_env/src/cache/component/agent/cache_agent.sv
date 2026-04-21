// cache_agent.sv
class cache_agent extends uvm_agent;
    cpu_cache_driver driver;
    uvm_sequencer #(cache_transaction) sequencer;
    
    `uvm_component_utils(cache_agent)
    
    function new(string name = "cache_agent", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

endclass


function void cache_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver = cpu_cache_driver::type_id::create("cpu_cache_driver", this);
    sequencer = uvm_sequencer #(cpu_cache_transaction)::type_id::create("cpu_cache_sqr", this);
endfunction
    
function void cache_agent::connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
endfunction


