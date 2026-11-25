// dirty_drain场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_dirty_drain_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_dirty_drain_sequence)
    function new(string name = "dcache_dirty_drain_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_dirty_drain_sequence::body();
    for (int set_index = 0; set_index < 4; set_index++) begin
        dirty_set(set_index);
        evict_set(set_index);
        check_evicted_set(set_index);
    end
    finish_scenario();
endtask
