// replacement_policy场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_replacement_policy_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_replacement_policy_sequence)
    function new(string name = "dcache_replacement_policy_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_replacement_policy_sequence::body();
    int before_reads;
    for (int tag = 1; tag <= 4; tag++) access(address(0, tag));
    repeat (8) access(address(0, 1));
    access(address(0, 5));
    before_reads = obs.reads;
    access(address(0, 1));
    record_check("FIFO oldest tag evicted despite hits", obs.reads-before_reads, 1);
    finish_scenario();
endtask
