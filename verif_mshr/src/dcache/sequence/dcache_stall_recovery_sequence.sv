// stall_recovery场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_stall_recovery_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_stall_recovery_sequence)
    function new(string name = "dcache_stall_recovery_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_stall_recovery_sequence::body();
    dirty_set(0);
    cfg.write_response_enable = 0;
    cfg.cpu_read_ready = 0;
    fork
        begin
            for (int tag = 5; tag < 13; tag++) access(address(0, tag), 0, 0, 0);
        end
        begin
            obs.wait_cycles(128);
            cfg.cpu_read_ready = 1;
            obs.wait_cycles(32);
            cfg.write_response_enable = 1;
        end
    join
    finish_scenario();
    required_hits["cpu_stall"] = 8;
    required_hits["cpu_read_stall"] = 8;
endtask
