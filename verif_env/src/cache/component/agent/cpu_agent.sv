// cpu_agent.sv
class cpu_agent extends uvm_agent;
    cpu_driver cpu_drv;
    cpu_in_monitor cpu_in_mon;
    uvm_sequencer #(cpu_req_transaction) cpu_req_sqr;

    
    `uvm_component_utils(cpu_agent)
    
    function new(string name = "cpu_agent", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

endclass


function void cpu_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cpu_drv = cpu_driver::type_id::create("cpu_driver", this);
    cpu_in_mon = cpu_in_monitor::type_id::create("cpu_in_monitor", this);
    cpu_req_sqr = uvm_sequencer #(cpu_req_transaction)::type_id::create("cpu_req_sqr", this);

endfunction
    
function void cpu_agent::connect_phase(uvm_phase phase);
    cpu_drv.seq_item_port.connect(cpu_req_sqr.seq_item_export);
endfunction


