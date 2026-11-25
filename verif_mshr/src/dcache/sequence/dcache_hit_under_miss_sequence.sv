// hit_under_miss场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_hit_under_miss_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_hit_under_miss_sequence)
    function new(string name = "dcache_hit_under_miss_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_hit_under_miss_sequence::body();
    int before_responses;
    access(address(0, 1));
    obs.wait_empty();
    cfg.read_response_enable = 0;
    before_responses = obs.responses;
    access(address(1, 1), 0, 0, 0);
    for (int index = 0; index < 16; index++) access(address(0, 1, index), 0, 0, 0);
    obs.wait_cycles(64);
    record_check("warm responses complete while miss is held", obs.responses-before_responses, 16);
    record_check("one memory read remains unreturned", obs.reads-obs.read_acks, 1);
    finish_scenario();
endtask
