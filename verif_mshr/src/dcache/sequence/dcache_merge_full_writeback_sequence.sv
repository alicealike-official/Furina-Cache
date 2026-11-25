class dcache_merge_full_writeback_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_merge_full_writeback_sequence)
    function new(string name = "dcache_merge_full_writeback_sequence");
        super.new(name);
    endfunction
    // 保持WBB全满，同时向已有MSHR行追加请求，检查合并路径仍可接受。
    task body();
        dirty_set(0);
        cfg.write_response_enable = 0;
        for (int tag = 5; tag < 8; tag++) access(address(0,tag));
        cfg.read_response_enable = 0;
        access(address(0,8),0,0,0);
        obs.wait_cycles(8);
        record_check("all WBB slots awaiting acknowledgement",obs.writes-obs.write_acks,4);
        access(address(0,8,1),1,'h97530001,0);
        obs.wait_cycles(4);
        finish_scenario();
        required_probe_hits["merge_bypasses_wbb_full"] = 1;
    endtask
endclass
