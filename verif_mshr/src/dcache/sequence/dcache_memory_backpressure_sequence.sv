// memory_backpressure场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_memory_backpressure_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_memory_backpressure_sequence)
    function new(string name = "dcache_memory_backpressure_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_memory_backpressure_sequence::body();
    cfg.read_request_enable = 0;
    access(address(0, 1), 0, 0, 0);
    obs.wait_cycles(16);
    cfg.read_request_enable = 1;
    obs.wait_empty();
    dirty_set(1);
    cfg.write_request_enable = 0;
    access(address(1, 5), 0, 0, 0);
    obs.wait_cycles(32);
    finish_scenario();
    required_hits["memory_read_stall"] = 8;
    required_hits["memory_write_stall"] = 8;
endtask
