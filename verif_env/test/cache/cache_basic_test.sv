// cache_basic_test.sv
class cache_basic_test extends uvm_test;
    cache_environment env;
    
    `uvm_component_utils(cache_basic_test)
    
    function new(string name = "cache_basic_test", 
                    uvm_component parent = null);
        super.new(name, parent);    
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

    
function void cache_basic_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cache_environment::type_id::create("cache_environment", this);
endfunction

task cache_basic_test::run_phase(uvm_phase phase);
    cache_base_virtual_sequence vseq;
    
    phase.raise_objection(this);
    
    vseq = cache_base_virtual_sequence::type_id::create("vseq");
    vseq.start(null);  // virtual sequence不需要sequencer
    
    phase.drop_objection(this);
endtask