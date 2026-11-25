class dcache_pipeline_windows_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_pipeline_windows_sequence)
    function new(string name = "dcache_pipeline_windows_sequence");
        super.new(name);
    endfunction
    // 对齐fill与CPU前后级窗口，检查Stage2重查当前匹配，不使用旧估计。
    task body();
        int base_alloc;
        // 变化响应放行沿，覆盖Stage1可合并但Stage2已经不可合并的窗口。
        for (int offset = 0; offset < 5; offset++) begin
            cfg.read_response_enable = 0;
            access(address(offset,1),0,0,0);
            obs.wait_cycles(8);
            cfg.read_response_not_before_cycle = obs.cycle + 1 + offset;
            cfg.read_response_enable = 1;
            access(address(offset,1,1),1,'h98760000+offset,0);
            finish_scenario();
        end
        // 连续两拍同块冷请求，第二笔Stage1估计时尚未分配，Stage2须看到上一笔新Entry。
        cfg.continuous_cpu = 1;
        cfg.read_response_enable = 0;
        access(address(12,1),0,0,0);
        access(address(12,1,1),0,0,0);
        finish_scenario();
        required_probe_hits["stage_merge_qualification_changed"] = 1;
        required_probe_hits["stage_new_entry_visible"] = 1;
        required_probe_hits["fill_during_request_pipeline"] = 1;
    endtask
endclass
