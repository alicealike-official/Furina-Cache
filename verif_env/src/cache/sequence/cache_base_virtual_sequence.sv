class cache_base_virtual_sequence extends uvm_sequence;
    `uvm_object_utils(cache_base_virtual_sequence)

    uvm_sequencer#(cpu_cache_transaction) cpu_cache_sqr;
    uvm_sequencer#(mem_cache_transaction) mem_cache_sqr;
    function new(string name = "cache_base_virtual_sequence");
        super.new();
    endfunction
    extern virtual task body();
endclass

task body();
    cpu_cache_sequence cpu_cache_seq;
    mem_cache_sequence mem_cache_seq;

    if(!uvm_config_db #(uvm_sequencer #(cpu_cache_transaction))::get(
        null, get_full_name(), "cpu_cache_sqr", cpu_cache_sqr))
    `fatal("CPU-Cache sequencer not found in config_db")

    if(!uvm_config_db #(uvm_sequencer #(mem_cache_transaction))::get(
        null, get_full_name(), "mem_cache_sqr", mem_cache_sqr))
    `fatal("MEM-Cache sequencer not found in config_db")

    cpu_cache_seq = cpu_cache_sequence::type_id::create("cpu_cache_seq");
    mem_cache_seq = mem_cache_sequence::type_id::create("mem_cache_seq");

    fork
        cpu_cache_seq.start(cpu_cache_sqr);
        mem_cache_seq.start(mem_cache_sqr);
    join
endtask