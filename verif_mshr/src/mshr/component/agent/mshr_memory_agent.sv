class mshr_memory_agent extends uvm_agent;
    mshr_memory_driver driver;

    `uvm_component_utils(mshr_memory_agent)

    function new(string name = "mshr_memory_agent",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);

endclass

function void mshr_memory_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver = mshr_memory_driver::type_id::create("driver", this);
endfunction
