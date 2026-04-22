// cpu_cache_agent.sv
class cpu_cache_agent extends uvm_agent;
    cpu_cache_driver driver;
    uvm_sequencer #(cpu_cache_transaction) sequencer;
    
    `uvm_component_utils(cpu_cache_agent)
    
    function new(string name = "cpu_cache_agent", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

endclass


function void cpu_cache_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver = cpu_cache_driver::type_id::create("cpu_cache_driver", this);
    sequencer = uvm_sequencer #(cpu_cache_transaction)::type_id::create("cpu_cache_sqr", this);
endfunction
    
function void cpu_cache_agent::connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
endfunction


