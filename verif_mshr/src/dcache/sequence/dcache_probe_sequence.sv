// 激励仍从CPU/内存正常接口进入；内部探针只提供实际事件与等待条件。
class dcache_probe_sequence extends dcache_scenario_sequence;
    dcache_probe_monitor probe_monitor;
    int required_probe_hits[string];
    `uvm_object_utils(dcache_probe_sequence)
    function new(string name = "dcache_probe_sequence");
        super.new(name);
    endfunction
    task pre_body();
        dcache_sequencer sequencer;
        super.pre_body();
        // 【防御性检查】只有启用真实探针的环境才允许启动本类case。
        if (!$cast(sequencer, get_sequencer()) || sequencer.probe_monitor == null) begin
            `fatal("Probe scenario requires internal monitor", "DCACHE_PROBE_CONFIG")
        end
        probe_monitor = sequencer.probe_monitor;
    endtask
    // 等待真实内部事件达到目标，不使用参考模型的状态推测是否发生。
    task wait_probe(string label, int target);
        while (!probe_monitor.hits.exists(label) || probe_monitor.hits[label] < target) begin
            @probe_monitor.sampled;
        end
    endtask
endclass
