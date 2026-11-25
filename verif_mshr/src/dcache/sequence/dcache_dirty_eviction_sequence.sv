// dirty_eviction场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_dirty_eviction_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_dirty_eviction_sequence)
    function new(string name = "dcache_dirty_eviction_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_dirty_eviction_sequence::body();
    dirty_set(0);
    evict_set(0);
    check_evicted_set(0);
    for (int tag = 1; tag <= 4; tag++) begin
        for (int word = 0; word < 16; word++) access(address(0, tag, word));
    end
    finish_scenario();
endtask
