class cache_base_virtual_sequence extends uvm_sequence;
    `uvm_object_utils(cache_base_virtual_sequence)

    uvm_sequencer#(cpu_req_transaction) cpu_req_sqr;
    // uvm_sequencer#(mem_cache_transaction) mem_cache_sqr;
    function new(string name = "cache_base_virtual_sequence");
        super.new();
    endfunction
    extern virtual task body();
endclass

task cache_base_virtual_sequence::body();
    cpu_basic_sequence cpu_req_seq;

    if(!uvm_config_db #(uvm_sequencer #(cpu_req_transaction))::get(
        null, "", "cpu_req_sqr", cpu_req_sqr))
    `fatal("CPU sequencer not found in config_db")

    cpu_req_seq = cpu_basic_sequence::type_id::create("cpu_req_seq");

    fork
        cpu_req_seq.start(cpu_req_sqr);
    join
endtask