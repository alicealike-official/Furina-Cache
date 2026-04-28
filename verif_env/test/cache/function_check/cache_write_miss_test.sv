// cache_write_miss_test.sv
class cache_write_miss_test extends cache_basic_test;
    
    `uvm_component_utils(cache_write_miss_test)
    
    function new(string name = "cache_write_miss_test", 
                    uvm_component parent = null);
        super.new(name, parent);    
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

    
function void cache_write_miss_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
endfunction

task cache_write_miss_test::run_phase(uvm_phase phase);
    //cache_base_virtual_sequence vseq;
    cpu_write_miss_sequence seq;
    
    phase.raise_objection(this);


    // vseq = cache_base_virtual_sequence::type_id::create("vseq");
    // vseq.start(null);
    seq = cpu_write_miss_sequence::type_id::create("seq");

    seq.start(env.cpu_agt.cpu_req_sqr);
    
    phase.drop_objection(this);
endtask