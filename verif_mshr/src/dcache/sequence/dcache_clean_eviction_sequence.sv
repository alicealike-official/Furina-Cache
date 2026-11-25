// clean_eviction场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_clean_eviction_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_clean_eviction_sequence)
    function new(string name = "dcache_clean_eviction_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_clean_eviction_sequence::body();
    for (int tag = 1; tag <= 12; tag++) access(address(0, tag));
    finish_scenario();
    record_check("all distinct cold blocks fetched", obs.reads, 12);
    record_check("clean eviction never writes memory", obs.writes, 0);
endtask
