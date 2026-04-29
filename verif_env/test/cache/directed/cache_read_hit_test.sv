// cache_read_hit_test.sv
class cache_read_hit_test extends cache_basic_test;
    
    `uvm_component_utils(cache_read_hit_test)
    
    function new(string name = "cache_read_hit_test", 
                    uvm_component parent = null);
        super.new(name, parent);    
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

    
function void cache_read_hit_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
endfunction

task cache_read_hit_test::run_phase(uvm_phase phase);
    //cache_base_virtual_sequence vseq;
    cpu_read_hit_sequence seq;
    
    phase.raise_objection(this);


    // vseq = cache_base_virtual_sequence::type_id::create("vseq");
    // vseq.start(null);
    seq = cpu_read_hit_sequence::type_id::create("seq");

    seq.start(env.cpu_agt.cpu_req_sqr);
    
    phase.drop_objection(this);
endtask