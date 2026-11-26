// 独立性能激励；每次仿真仅一个场景，保证冷未命中对照没有跨场景预热污染。
class dcache_perf_sequence extends dcache_scenario_sequence;
    string scenario = "hit_read";
    bit serialized = 0;
    int request_count = 1024;
    int requests_per_line = 1;
    dcache_perf_monitor perf;
    `uvm_object_utils(dcache_perf_sequence)
    function new(string name = "dcache_perf_sequence");
        super.new(name);
    endfunction
    task pre_body();
        dcache_sequencer sequencer;
        super.pre_body();
        // 【防御性检查】perf只能在显式创建测量组件的环境运行。
        if (!$cast(sequencer, get_sequencer()) || sequencer.perf_monitor == null) begin
            `fatal("Performance monitor missing", "DCACHE_PERF_CONFIG")
        end
        perf = sequencer.perf_monitor;
    endtask

    // 冷流各行唯一且连续分布到不同set，同一配置的串行/连续提交使用完全相同地址。
    function bit [ADDR_WIDTH-1:0] cold_address(int line_index, int word_index = 0);
        return address(line_index % NUM_SETS, 64 + line_index / NUM_SETS, word_index);
    endfunction

    // 每字数据不同，性能测试也能暴露地址/字位置或数据版本错误；原数据检查链始终开启。
    function bit [LINE_WIDTH-1:0] initial_line(int line_index);
        bit [LINE_WIDTH-1:0] line;
        for (int word_index = 0; word_index < LINE_WIDTH / DATA_WIDTH; word_index++) begin
            line[word_index*DATA_WIDTH +: DATA_WIDTH] = 32'h65000000 + line_index*256 + word_index;
        end
        return line;
    endfunction

    // 仅预置外部原C++ SparseMemory和独立CPU期望，不后门写Cache，且全部发生在测量前。
    task prepare_cold_lines(int line_count);
        for (int line_index = 0; line_index < line_count; line_index++) begin
            preload(cold_address(line_index), initial_line(line_index));
        end
    endtask

    // 四条热行在不同set，不发生替换；预热的取行、延迟和资源使用不进入测量窗口。
    task warm_hot_lines();
        for (int set_index = 0; set_index < 4; set_index++) begin
            preload(address(set_index, 1), initial_line(set_index));
            access(address(set_index, 1));
        end
    endtask

    // 所有set的四路均准备为脏，新行也采用写分配，使整个测量流持续产生脏淘汰。
    task warm_dirty_cache();
        int line_index;
        line_index = 0;
        for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
            for (int tag = 1; tag <= NUM_WAYS; tag++) begin
                preload(address(set_index, tag), initial_line(1024 + line_index));
                access(address(set_index, tag), 1, 32'hc1000000 + line_index);
                line_index++;
            end
        end
    endtask

    // 预热及所有已发事务排空后才开始，起点自动取后续首个真实CPU valid采样。
    task begin_measurement();
        obs.wait_empty();
        while (!perf.is_settled()) obs.wait_cycles(1);
        @(negedge perf.vif.clk);
        perf.begin_window(scenario, serialized ? "serial" : "stream", request_count, requests_per_line);
    endtask

    // 分别形成读、写、混合命中流；字偏移循环变化，数据源仍由sequence指定。
    task run_hit_stream();
        bit is_write;
        for (int index = 0; index < request_count; index++) begin
            is_write = scenario == "hit_write" || scenario == "hit_mixed" && index % 2 != 0;
            access(address(index % 4, 1, (index/4) % (LINE_WIDTH/DATA_WIDTH)),
                is_write, 32'hb1000000+index, serialized);
        end
    endtask

    // 每笔都是新行；serial仅限制CPU同时一笔，DUT与后台机制不改变。
    task run_independent_misses();
        for (int index = 0; index < request_count; index++) begin
            access(cold_address(index, index % (LINE_WIDTH/DATA_WIDTH)), 0, 0, serialized);
        end
    endtask

    // 每组1/2/4笔访问同一冷行不同字；不人为等待返回，快速返回后的hit单独计数。
    task run_same_line_groups();
        for (int line_index = 0; line_index < request_count/requests_per_line; line_index++) begin
            for (int word_index = 0; word_index < requests_per_line; word_index++) begin
                access(cold_address(line_index, word_index), 0, 0, 0);
            end
        end
    endtask

    // 全冷写流替换初始脏行；测量结束只等已发写回确认，不额外flush最后留在Cache的脏行。
    task run_dirty_evictions();
        for (int index = 0; index < request_count; index++) begin
            access(cold_address(index), 1, 32'hd2000000+index, serialized);
        end
    endtask

    // 检查测量确实走了目标路径，不把TB空拍或未命中场景混进宣称的峰值结果。
    function void check_measurement();
        dcache_perf_result result;
        result = perf.result;
        if (!serialized) record_check("stream source must not insert idle cycles", result.idle_to_last_accept, 0);
        else record_check("serial CPU baseline outstanding", result.max_cpu_outstanding, 1);
        if (scenario inside {"hit_read", "hit_write", "hit_mixed"}) begin
            record_check("warm hit commits", result.hit_count, request_count);
            record_check("warm flow memory reads", result.mem_reads, 0);
            record_check("warm flow memory writes", result.mem_writes, 0);
            if (!serialized) record_check("one hit accepted each cycle", int'(result.acceptance_cycles()), request_count);
        end else if (scenario == "independent") begin
            record_check("independent cold allocations", result.alloc_count, request_count);
            record_check("independent memory reads", result.mem_reads, request_count);
            record_check("clean stream must not write memory", result.mem_writes, 0);
        end else if (scenario == "merge") begin
            record_check("one fetch for each cold group", result.mem_reads, request_count/requests_per_line);
            record_check("one allocation for each cold group", result.alloc_count, request_count/requests_per_line);
            record_check("merge flow memory writes", result.mem_writes, 0);
            if (cfg.read_latency_cycles >= 8) begin
                record_check("group requests merged before response", result.merge_count,
                    request_count-request_count/requests_per_line);
            end
        end else begin
            record_check("dirty cold allocations", result.alloc_count, request_count);
            record_check("dirty stream memory reads", result.mem_reads, request_count);
            record_check("dirty stream memory writes", result.mem_writes, request_count);
            record_check("dirty stream reservations", result.reserve_count, request_count);
        end
    endfunction

    // 一个case只做一个窗口；所有对照由runner在新仿真中重放，避免Cache状态污染。
    task body();
        // 【防御性检查】参数只允许当前性能矩阵支持的有效组合。
        if (!(scenario inside {"hit_read", "hit_write", "hit_mixed", "independent", "merge", "dirty"}) ||
            request_count <= 0 || !(requests_per_line inside {1,2,4}) || request_count % requests_per_line != 0 ||
            scenario == "merge" && serialized) begin
            `fatal("Invalid performance scenario parameters", "DCACHE_PERF_CONFIG")
        end
        if (scenario inside {"hit_read", "hit_write", "hit_mixed"}) warm_hot_lines();
        else begin
            prepare_cold_lines(scenario == "merge" ? request_count/requests_per_line : request_count);
            if (scenario == "dirty") warm_dirty_cache();
        end

        begin_measurement();
        case (scenario)
            "hit_read", "hit_write", "hit_mixed": run_hit_stream();
            "independent": run_independent_misses();
            "merge": run_same_line_groups();
            "dirty": run_dirty_evictions();
        endcase

        obs.wait_empty();
        while (!perf.is_settled()) obs.wait_cycles(1);
        @(negedge perf.vif.clk);
        perf.finish_window();
        check_measurement();
    endtask
endclass
