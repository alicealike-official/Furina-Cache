// raw_pipeline场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_raw_pipeline_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_raw_pipeline_sequence)
    function new(string name = "dcache_raw_pipeline_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_raw_pipeline_sequence::body();
    cfg.continuous_cpu = 1;
    access(address(0, 1));
    for (int round_index = 0; round_index < 32; round_index++) begin
        access(address(0, 1), 1, 'h11000000 + round_index, 0);
        access(address(0, 1), 0, 0, 0);
        access(address(0, 1), 1, 'h22000000 + round_index, 0);
        access(address(0, 1), 0, 0, 0);
    end
    finish_scenario();
    required_hits["consecutive_cpu"] = 32;
endtask
