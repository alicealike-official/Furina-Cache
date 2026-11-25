class dcache_response_arbitration_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_response_arbitration_sequence)
    function new(string name = "dcache_response_arbitration_sequence");
        super.new(name);
    endfunction
    task body();
        cfg.continuous_cpu = 1;
        access(address(0, 1));
        for (int mode = 0; mode < 4; mode++) begin
            // 冷行准备replay，热行连续命中；四种读写来源组合各运行一次。
            cfg.read_response_enable = 0;
            access(address(mode+1, 1), mode == 1 || mode == 2, 'haabbccdd, 0);
            obs.wait_cycles(4);
            cfg.read_response_enable = 1;
            for (int index = 0; index < 64; index++) begin
                access(address(0, 1, index%16), mode == 1 || mode == 3, 'h78900000+index, 0);
            end
            obs.wait_empty();
        end
        finish_scenario();
        required_probe_hits["read_priority"] = 1;
        required_probe_hits["write_priority"] = 1;
        required_probe_hits["hit_read_replay_write"] = 1;
        required_probe_hits["hit_write_replay_read"] = 1;
    endtask
endclass
