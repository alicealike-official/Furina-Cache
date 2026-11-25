class dcache_stage_boundary_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_stage_boundary_sequence)
    function new(string name = "dcache_stage_boundary_sequence");
        super.new(name);
    endfunction

    // 连续五个冷请求，使第五笔Stage1接受时尚有空Entry、Stage2时却已用完。
    task fill_entry_pipeline(bit same_set);
        cfg.continuous_cpu = 1;
        cfg.read_response_enable = 0;
        fork
            begin
                for (int index = 0; index < 5; index++) begin
                    access(address(same_set ? 20 : 8 + index, same_set ? index + 1 : 1), 0, 0, 0);
                end
            end
            begin
                obs.wait_cycles(48);
                cfg.read_response_enable = 1;
            end
        join
        finish_scenario();
    endtask

    // 扫描CPU请求进入时刻，覆盖同一接受沿旧Entry最后replay、下一拍重新使用该Entry。
    task release_before_alloc();
        cfg.continuous_cpu = 0;
        for (int offset = 0; offset < 9; offset++) begin
            cfg.read_response_enable = 0;
            access(address(24, offset + 1), 0, 0, 0);
            obs.wait_cycles(8);
            cfg.read_response_enable = 1;
            obs.wait_cycles(offset);
            access(address(25, offset + 1), 0, 0, 0);
            finish_scenario();
        end
    endtask

    // 分别建立不同set的Entry不足、同set全锁，以及释放到重新分配的沿边界。
    task body();
        fill_entry_pipeline(0);
        fill_entry_pipeline(1);
        release_before_alloc();
        required_probe_hits["stage2_no_entry"] = 1;
        required_probe_hits["stage2_all_ways_locked"] = 1;
        required_probe_hits["accepted_then_entry_reused"] = 1;
    endtask
endclass
