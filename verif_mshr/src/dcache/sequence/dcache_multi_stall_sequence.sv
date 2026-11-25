class dcache_multi_stall_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_multi_stall_sequence)
    function new(string name = "dcache_multi_stall_sequence");
        super.new(name);
    endfunction

    // 前三笔脏淘汰保持未确认，同时填入新脏行；为第四笔和紧随请求留下流水窗口。
    task prepare_pressure();
        dirty_set(0);
        cfg.write_response_enable = 0;
        cfg.cpu_write_ready = 0;
        for (int tag = 5; tag < 8; tag++) begin
            access(address(0, tag), 1, 'h45200000 + tag, 0);
            obs.wait_cycles(20);
        end
    endtask

    // 第四笔冷写占最后WBB槽；紧随的冷写先进入流水，再同时等待WBB与CPU响应空间。
    task run_frozen_pair();
        cfg.continuous_cpu = 1;
        access(address(0, 8), 1, 'h45200008, 0);
        access(address(0, 9), 1, 'h45200009, 0);
        obs.wait_cycles(40);
        cfg.cpu_write_ready = 1;
        obs.wait_cycles(16);
        cfg.write_response_enable = 1;
    endtask

    // 分两次释放外部阻塞，最终所有请求完成；每种内部冻结条件必须实际命中。
    task body();
        prepare_pressure();
        run_frozen_pair();
        finish_scenario();
        required_probe_hits["two_stall_causes"] = 1;
        required_probe_hits["dirty_wait_after_fifo_release"] = 1;
    endtask
endclass
