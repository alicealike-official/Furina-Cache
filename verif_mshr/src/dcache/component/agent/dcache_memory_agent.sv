class dcache_memory_agent extends uvm_agent;
    dcache_memory_driver driver;
    `uvm_component_utils(dcache_memory_agent)
    function new(string name = "dcache_memory_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = dcache_memory_driver::type_id::create("driver", this);
    endfunction
endclass
