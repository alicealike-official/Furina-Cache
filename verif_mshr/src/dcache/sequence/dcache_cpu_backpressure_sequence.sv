// cpu_backpressure场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_cpu_backpressure_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_cpu_backpressure_sequence)
    function new(string name = "dcache_cpu_backpressure_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_cpu_backpressure_sequence::body();
    access(address(0, 1));
    for (int mode = 0; mode < 3; mode++) begin
        cfg.cpu_read_ready = mode == 1;
        cfg.cpu_write_ready = mode == 0;
        fork
            begin
                for (int index = 0; index < 24; index++)
                    access(address(0, 1, index % 16), mode == 1 || (mode == 2 && index % 2 != 0),
                        'h56ab0000 + index, 0);
            end
            begin
                obs.wait_cycles(128);
                cfg.cpu_read_ready = 1;
                cfg.cpu_write_ready = 1;
            end
        join
        obs.wait_empty();
    end
    finish_scenario();
    required_hits["cpu_read_stall"] = 8;
    required_hits["cpu_write_stall"] = 8;
    required_hits["cpu_stall"] = 8;
endtask
