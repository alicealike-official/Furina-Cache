// response_latency场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_response_latency_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_response_latency_sequence)
    function new(string name = "dcache_response_latency_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_response_latency_sequence::body();
    int delays[4] = '{1,2,7,32};
    int before_reads;
    foreach (delays[index]) begin
        cfg.read_latency_cycles = delays[index];
        cfg.write_latency_cycles = delays[index];
        dirty_set(index);
        evict_set(index);
        check_evicted_set(index);
        record_check("exact read delay observed", obs.read_delays.exists(delays[index]) ? obs.read_delays[delays[index]] : 0, 1, 1);
        record_check("exact write delay observed", obs.write_delays.exists(delays[index]) ? obs.write_delays[delays[index]] : 0, 1, 1);
    end
    finish_scenario();
endtask
