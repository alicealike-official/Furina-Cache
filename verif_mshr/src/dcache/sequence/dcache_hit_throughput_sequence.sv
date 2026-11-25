// hit_throughput场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_hit_throughput_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_hit_throughput_sequence)
    function new(string name = "dcache_hit_throughput_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_hit_throughput_sequence::body();
    int before_reads;
    cfg.continuous_cpu = 1;
    access(address(0, 1));
    obs.wait_empty();
    before_reads = obs.reads;
    for (int index = 0; index < 128; index++) access(address(0, 1, index % 16), 0, 0, 0);
    finish_scenario();
    record_check("warm stream never refetches", obs.reads-before_reads, 0);
    record_check("consecutive hit burst", obs.max_cpu_burst, 128, 1);
endtask
