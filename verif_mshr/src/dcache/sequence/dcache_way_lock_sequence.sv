class dcache_way_lock_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_way_lock_sequence)
    function new(string name = "dcache_way_lock_sequence");
        super.new(name);
    endfunction
    task body();
        int before_reads;
        cfg.read_response_enable = 0;
        for (int tag = 1; tag <= 4; tag++) access(address(0, tag), 0, 0, 0);
        wait_probe("all_ways_locked", 4);
        // 同set第五行等待，后台响应放行后原请求继续；锁更新由真实alloc/最后replay核对。
        fork
            access(address(0, 5), 0, 0, 0);
            begin
                obs.wait_cycles(16);
                cfg.read_response_enable = 1;
            end
        join
        obs.wait_empty();
        before_reads = obs.reads;
        access(address(0, 5));
        record_check("released and filled line becomes a hit", obs.reads-before_reads, 0);
        // 不同set同时占用，用整个lockMask比较确认不会误锁别组。
        cfg.read_response_enable = 0;
        for (int set_index = 1; set_index <= 4; set_index++) access(address(set_index, 1), 0, 0, 0);
        finish_scenario();
        required_probe_hits["all_ways_locked"] = 4;
        required_probe_hits["entry_release"] = 9;
        required_probe_hits["fill_while_locked"] = 9;
    endtask
endclass
