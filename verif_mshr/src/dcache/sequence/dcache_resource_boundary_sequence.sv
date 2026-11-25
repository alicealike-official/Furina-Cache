class dcache_resource_boundary_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_resource_boundary_sequence)
    function new(string name = "dcache_resource_boundary_sequence");
        super.new(name);
    endfunction
    task body();
        int target_merges;
        // 四条Entry实际分配后，在满表期间向旧Entry追加Slot。
        cfg.read_response_enable = 0;
        for (int index = 0; index < 4; index++) access(address(index, 1), 0, 0, 0);
        wait_probe("alloc", 4);
        access(address(0, 1, 1), 1, 'h11223344, 0);
        access(address(0, 1, 2), 0, 0, 0);
        wait_probe("merge", 2);
        // CPU接受后一拍提交merge，将队首响应对齐到该提交沿。
        obs.wait_cycles(1);
        cfg.read_response_not_before_cycle = obs.cycle + 2;
        cfg.read_response_enable = 1;
        access(address(0, 1, 3), 1, 'h55667788, 0);
        obs.wait_empty();

        // 脏淘汰预留/push、WBB满响应和响应FIFO满边界由真实模块接口计数。
        dirty_set(8);
        cfg.write_response_enable = 0;
        evict_set(8);
        obs.wait_cycles(16);
        cfg.write_response_enable = 1;
        obs.wait_empty();
        cfg.cpu_read_ready = 0;
        fork
            begin
                for (int index = 0; index < 16; index++) access(address(0, 1, index), 0, 0, 0);
            end
            begin
                obs.wait_cycles(64);
                cfg.cpu_read_ready = 1;
            end
        join
        finish_scenario();
        required_probe_hits["last_entry_alloc"] = 1;
        required_probe_hits["full_entry_merge"] = 3;
        required_probe_hits["last_slot_merge"] = 1;
        required_probe_hits["last_slot_response"] = 1;
        required_probe_hits["full_entry_release"] = 1;
        required_probe_hits["dirty_atomic"] = 4;
        required_probe_hits["reserve_push"] = 4;
        required_probe_hits["full_wbb_response"] = 1;
        required_probe_hits["read_fifo_full"] = 1;
    endtask
endclass
