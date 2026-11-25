// eviction_window场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_eviction_window_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_eviction_window_sequence)
    function new(string name = "dcache_eviction_window_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_eviction_window_sequence::body();
    cfg.continuous_cpu = 1;
    for (int tag = 1; tag <= 4; tag++) access(address(0, tag));
    access(address(0, 1), 1, 'h1234abcd, 0);
    access(address(0, 5), 0, 0, 0);
    access(address(0, 1), 0, 0, 0);
    finish_scenario();
    record_check("just-written victim actually written back", obs.writes, 1, 1);
    required_hits["consecutive_cpu"] = 1;
endtask
