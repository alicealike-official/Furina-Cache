class wbb_memory_agent extends uvm_agent;
    wbb_memory_driver driver;
    `uvm_component_utils(wbb_memory_agent)

    function new(string name = "wbb_memory_agent",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
endclass

function void wbb_memory_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // Reactive responder: no sequence is needed to invent memory acknowledgments.
    driver = wbb_memory_driver::type_id::create("driver", this);
endfunction
