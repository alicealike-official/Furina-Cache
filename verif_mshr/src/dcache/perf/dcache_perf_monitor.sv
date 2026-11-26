// 性能旁观者只记录真实IO，不驱动接口，不替代原C++模型或scoreboard。
class dcache_perf_monitor extends uvm_subscriber #(dcache_sample);
    virtual dcache_interface vif;
    virtual mshr_interface mshr_vif;
    virtual wbb_interface wbb_vif;
    virtual dcache_probe_interface probe;
    dcache_config cfg;
    dcache_perf_result result;
    longint cycle;
    bit measuring;
    bit cpu_pending[1 << CPU_ID_WIDTH];
    longint cpu_accepted_at[1 << CPU_ID_WIDTH];
    bit read_pending[1 << BUS_ID_WIDTH], write_pending[1 << BUS_ID_WIDTH];
    longint read_accepted_at[1 << BUS_ID_WIDTH], write_accepted_at[1 << BUS_ID_WIDTH];
    bit wbb_occupied[WBB_ENTRIES];
    `uvm_component_utils(dcache_perf_monitor)
    function new(string name = "dcache_perf_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】全部观察接口与配置必须来自所属环境，不创建默认替代对象。
        if (!uvm_config_db #(dcache_config)::get(this, "", "dcache_config", cfg) ||
            !uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", vif) ||
            !uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", mshr_vif) ||
            !uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", wbb_vif) ||
            !uvm_config_db #(virtual dcache_probe_interface)::get(this, "", "dcache_probe_vif", probe)) begin
            `fatal("Performance observation dependencies missing", "DCACHE_PERF_CONFIG")
        end
    endfunction

    // 始终记录实际WBB槽生命周期；测量从首个CPU valid采样开始，预热期间不计性能。
    function void write(dcache_sample sample);
        if (!sample.rst_n) begin
            foreach (wbb_occupied[slot]) wbb_occupied[slot] = 0;
            if (measuring) `fatal("Reset inside performance measurement", "DCACHE_PERF_RESET")
            return;
        end
        cycle++;
        if (measuring && !result.started && sample.cpu_valid) begin
            result.started = 1;
            result.first_present = cycle;
        end
        if (measuring && result.started) begin
            sample_resources(sample);
            record_cpu(sample);
            record_memory(sample);
            record_commits();
            if (result.responses > 0 && (sample.cpuReadResp_valid && sample.cpuReadResp_ready ||
                sample.cpuWriteResp_valid && sample.cpuWriteResp_ready ||
                sample.memReadResp_valid && sample.memReadResp_ready ||
                sample.memWriteResp_valid && sample.memWriteResp_ready)) save_completion_snapshot();
        end
        update_wbb_history(sample);
    endfunction

    // 以沿前真实锁矩阵计MSHR占用，WBB只按实际reserve/ack计数，不从模型推测占用。
    function void sample_resources(dcache_sample sample);
        int mshr_count;
        int wbb_count;
        mshr_count = $countones(mshr_vif.mon_cb.lockMask);
        wbb_count = 0;
        foreach (wbb_occupied[slot]) if (wbb_occupied[slot]) wbb_count++;
        result.mshr_sum += mshr_count;
        result.wbb_sum += wbb_count;
        if (mshr_count > result.peak_mshr) result.peak_mshr = mshr_count;
        if (wbb_count > result.peak_wbb) result.peak_wbb = wbb_count;
        if (sample.cpu_valid && !sample.cpu_ready) begin
            result.input_stalls++;
            if (!mshr_vif.mon_cb.hasFree) result.mshr_full_stalls++;
            if (wbb_vif.mon_cb.full) result.wbb_full_stalls++;
            if (mshr_vif.mon_cb.m0_hit && (!mshr_vif.mon_cb.m0_mergeable || !mshr_vif.mon_cb.m0_slotFree))
                result.same_line_stalls++;
        end
        if (!sample.cpu_valid) result.input_idle++;
        if (sample.memReadReq_valid && !sample.memReadReq_ready) result.mem_read_stalls++;
        if (sample.memWriteReq_valid && !sample.memWriteReq_ready) result.mem_write_stalls++;
    endfunction

    // 响应先完成旧ID，再记录本沿新请求；CPU延迟口径为接受沿到最终响应握手沿。
    function void record_cpu(dcache_sample sample);
        if (sample.cpuReadResp_valid && sample.cpuReadResp_ready) complete_cpu(sample.cpuReadResp_payload_id, 0);
        if (sample.cpuWriteResp_valid && sample.cpuWriteResp_ready) complete_cpu(sample.cpuWriteResp_payload_id, 1);
        if (sample.cpu_valid && sample.cpu_ready) begin
            cpu_pending[sample.cpu_payload_id] = 1;
            cpu_accepted_at[sample.cpu_payload_id] = cycle;
            if (result.requests == 0) result.first_accept = cycle;
            result.requests++;
            if (sample.cpu_payload_wrEn) result.write_requests++;
            else result.read_requests++;
            result.cpu_outstanding++;
            if (result.cpu_outstanding > result.max_cpu_outstanding) result.max_cpu_outstanding = result.cpu_outstanding;
            result.last_accept = cycle;
            result.stalls_to_last_accept = result.input_stalls;
            result.idle_to_last_accept = result.input_idle;
            result.mshr_full_at_last_accept = result.mshr_full_stalls;
            result.wbb_full_at_last_accept = result.wbb_full_stalls;
            result.same_line_at_last_accept = result.same_line_stalls;
        end
    endfunction

    // 延迟样本只对应测量窗口内实际接受过的ID，错误仍由原数据检查链报告并保留。
    function void complete_cpu(int id, bit is_write);
        if (!cpu_pending[id]) begin
            `error("Performance response has no measured CPU request", "DCACHE_PERF_OWNER")
            return;
        end
        if (is_write) result.write_latencies.push_back(int'(cycle-cpu_accepted_at[id]));
        else result.read_latencies.push_back(int'(cycle-cpu_accepted_at[id]));
        cpu_pending[id] = 0;
        result.responses++;
        result.cpu_outstanding--;
        result.last_response = cycle;
    endfunction

    // 实际内存延迟包括DUT对响应的反压，不能直接把配置L当作测量值。
    function void record_memory(dcache_sample sample);
        if (sample.memReadResp_valid && sample.memReadResp_ready) begin
            if (!read_pending[sample.memReadResp_payload_id]) `error("Unmeasured memory read response", "DCACHE_PERF_OWNER")
            result.memory_read_latencies.push_back(int'(cycle-read_accepted_at[sample.memReadResp_payload_id]));
            read_pending[sample.memReadResp_payload_id] = 0;
            result.mem_read_acks++;
        end
        if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
            if (!write_pending[sample.memWriteResp_payload_id]) `error("Unmeasured memory write response", "DCACHE_PERF_OWNER")
            result.memory_write_latencies.push_back(int'(cycle-write_accepted_at[sample.memWriteResp_payload_id]));
            write_pending[sample.memWriteResp_payload_id] = 0;
            result.mem_write_acks++;
        end
        if (sample.memReadReq_valid && sample.memReadReq_ready) begin
            read_pending[sample.memReadReq_payload_id] = 1;
            read_accepted_at[sample.memReadReq_payload_id] = cycle;
            result.mem_reads++;
        end
        if (sample.memWriteReq_valid && sample.memWriteReq_ready) begin
            write_pending[sample.memWriteReq_payload_id] = 1;
            write_accepted_at[sample.memWriteReq_payload_id] = cycle;
            result.mem_writes++;
        end
    endfunction

    // 区分实际hit、alloc和merge，防止把整行返回后的命中算成同行合并。
    function void record_commits();
        if (probe.mon_cb.hitRead || probe.mon_cb.hitWrite) result.hit_count++;
        if (mshr_vif.mon_cb.alloc_en) result.alloc_count++;
        if (mshr_vif.mon_cb.merge_en) result.merge_count++;
        if (wbb_vif.mon_cb.reserve_en && wbb_vif.mon_cb.reserveOk) result.reserve_count++;
    endfunction

    // 仅保存最后一次真实完成事件处的积分，排空检测额外等待的空拍不会摊薄资源利用率。
    function void save_completion_snapshot();
        result.last_completion = cycle;
        result.mshr_sum_at_completion = result.mshr_sum;
        result.wbb_sum_at_completion = result.wbb_sum;
        result.read_stalls_at_completion = result.mem_read_stalls;
        result.write_stalls_at_completion = result.mem_write_stalls;
    endfunction

    // 只是实际槽位所有权记录，复用原IP检查器验证输入合法性，不在这里另写WBB模型。
    function void update_wbb_history(dcache_sample sample);
        if (sample.memWriteResp_valid && sample.memWriteResp_ready && sample.memWriteResp_payload_id < WBB_ENTRIES)
            wbb_occupied[sample.memWriteResp_payload_id] = 0;
        if (wbb_vif.mon_cb.reserve_en && wbb_vif.mon_cb.reserveOk)
            wbb_occupied[wbb_vif.mon_cb.reserveSlot] = 1;
    endfunction

    // 原始有效输出、本地锁与WBB占用都已清空才结束测量，不要求未淘汰脏行回写。
    function bit is_settled();
        foreach (wbb_occupied[slot]) if (wbb_occupied[slot]) return 0;
        return mshr_vif.lockMask === '0 && probe.s1Valid === 1'b0 && wbb_vif.push_en === 1'b0 &&
            {vif.cpu_valid, vif.cpuReadResp_valid, vif.cpuWriteResp_valid, vif.memReadReq_valid,
             vif.memWriteReq_valid, vif.memReadResp_valid, vif.memWriteResp_valid} === 7'b0000000;
    endfunction

    // 测量前必须完全静止；开始时刻延迟到首个valid，排除TB启动首项的准备时间。
    function void begin_window(string scenario, string submission, int requests, int group_size);
        // 【防御性检查】每个性能case只允许一个无重叠的有效测量窗口。
        if (measuring || !is_settled() || requests <= 0) begin
            `fatal("Performance window must begin from an idle DUT", "DCACHE_PERF_WINDOW")
        end
        result = dcache_perf_result::type_id::create("result");
        result.scenario = scenario;
        result.submission = submission;
        result.expected_requests = requests;
        result.group_size = group_size;
        result.configured_read_latency = cfg.read_latency_cycles;
        result.configured_write_latency = cfg.write_latency_cycles;
        measuring = 1;
    endfunction

    // 先核对窗口完整性，再导出统计；不因性能数值不好而跳过正确性检查。
    function void finish_window();
        if (!measuring || !result.started || !is_settled()) begin
            `fatal("Performance window finished before settling", "DCACHE_PERF_WINDOW")
        end
        if (result.requests != result.expected_requests || result.responses != result.expected_requests ||
            result.mem_reads != result.mem_read_acks || result.mem_writes != result.mem_write_acks ||
            result.requests != result.hit_count + result.alloc_count + result.merge_count ||
            result.presentation_cycles() != result.requests + result.stalls_to_last_accept + result.idle_to_last_accept) begin
            `error("Performance measurement counts do not balance", "DCACHE_PERF_COUNTS")
        end
        measuring = 0;
        result.write_json(cfg.perf_result_file);
        `info($sformatf("scenario=%s submission=%s requests=%0d cycles=%0d throughput=%0.6f peak_mshr=%0d peak_wbb=%0d",
            result.scenario, result.submission, result.requests, result.cpu_cycles(),
            real'(result.responses)/result.cpu_cycles(), result.peak_mshr, result.peak_wbb), "DCACHE_PERF_RESULT")
    endfunction
endclass
