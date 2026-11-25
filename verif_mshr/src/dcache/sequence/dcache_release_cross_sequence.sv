class dcache_release_cross_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_release_cross_sequence)
    function new(string name = "dcache_release_cross_sequence");
        super.new(name);
    endfunction
    // 扫描响应放行拍，要求最后一个Entry分配和旧Entry的内存返回确实同拍。
    task entry_boundary();
        for (int offset = 1; offset <= 4; offset++) begin
            cfg.read_response_enable = 0;
            for (int index = 0; index < 3; index++) begin
                access(address(index, offset), 0, 0, 0);
            end
            obs.wait_cycles(8);
            cfg.read_response_not_before_cycle = obs.cycle + offset;
            cfg.read_response_enable = 1;
            access(address(3, offset), 0, 0, 0);
            finish_scenario();
        end
    endtask

    // WBB已有三笔未确认写回时，扫描最后空槽预留与旧写回确认的重叠窗口。
    task writeback_boundary();
        for (int offset = 1; offset <= 4; offset++) begin
            dirty_set(8 + offset);
            cfg.write_response_enable = 0;
            for (int tag = 5; tag < 8; tag++) access(address(8 + offset, tag));
            obs.wait_cycles(8);
            cfg.write_response_not_before_cycle = obs.cycle + offset;
            cfg.write_response_enable = 1;
            access(address(8 + offset, 8), 0, 0, 0);
            finish_scenario();
        end
    endtask

    // 两种资源边界分别建立，避免前一阶段残留事务影响下一阶段。
    task body();
        entry_boundary();
        writeback_boundary();
        required_probe_hits["last_entry_with_response"] = 1;
        required_probe_hits["last_wbb_with_ack"] = 1;
    endtask
endclass
