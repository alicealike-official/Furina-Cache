    typedef struct packed {
        bit [4:0] id;
        bit [31:0] data;
    } fifo_read_t;
    fifo_read_t fifo_read_records[$];
    int fifo_write_records[$];
    bit released_previous_cycle;
    int released_entry;
    bit [15:0] words_written_after_fill[128];
    bit filled_from_w2[128];
    int writeback_outstanding;
    bit same_edge_read_pending[1 << CPU_ID_WIDTH];
    logic [DATA_WIDTH-1:0] same_edge_write_data[1 << CPU_ID_WIDTH];
    bit previous_cpu_accept;
    bit previous_m0_hit;
    bit previous_m0_mergeable;
    bit [1:0] previous_m0_entry;
    int latency_accept_commit[int];
    int latency_commit_enqueue[int];
    int latency_enqueue_response[int];

    // 依次检查策略、旁路/冻结、FIFO与事件交叉；所有输入来自同一沿前快照。
    function void extended_checks(dcache_probe_sample sample);
        check_ready_and_windows(sample);
        check_metadata(sample);
        check_fifo_policy(sample);
        check_bypass_and_freeze(sample);
        check_read_during_write(sample);
        check_fifo_transfers(sample);
        count_pipeline_windows(sample);
        count_memory_combinations(sample);
    endfunction

    // 复用原C++ FIFO策略，从实际命中和fill更新独立实例，比较所有set顺序及实际victim。
    function void check_fifo_policy(dcache_probe_sample sample);
        bit [255:0] expected_order;
        bit [3:0] locked;
        bit [3:0] free_ways;
        int candidate;
        locked = sample.m_lockMask[int'(sample.s1Index)*4 +: 4];
        free_ways = ~sample.cache_inspect_valid & ~locked;
        // dcache_fifo_step位于dpi/dcache_dpi.cpp，仅包装原FifoPolicy并导出其顺序。
        if (!dcache_fifo_step(policy_handle, 0, sample.hitRead || sample.hitWrite,
            sample.s1Index, sample.hitWay, sample.cache_w2_en, sample.cache_w2_index, sample.cache_w2_way,
            sample.s1Index, sample.cache_inspect_valid, locked, candidate, expected_order)) begin
            `fatal(dcache_last_error(), "DCACHE_POLICY_DPI")
        end
        require_condition(sample.fifo_order === expected_order, "FIFO order differs from architectural hit/fill updates");
        if (sample.m_alloc_en) begin
            require_condition(candidate >= 0 && sample.m_alloc_way === 2'(candidate), "Victim differs from FIFO preference after excluding locks");
            if (free_ways != 0 && locked != 0) count("free_way_with_locks");
            if (free_ways == 0 && locked != 0) count("policy_skips_lock");
        end
        if (sample.hitRead || sample.hitWrite) count("policy_hit_checked");
        if (sample.cache_w2_en) count("policy_fill_checked");
        if (previous != null && !previous.cache_w2_en) count("policy_no_fill_hold_checked");
    endfunction

    // 旁路选择来自规格比较键；冻结时请求字段及R1刷新地址保持，不依赖RAM同址读写原语。
    function void check_bypass_and_freeze(dcache_probe_sample sample);
        bit expected_bypass;
        expected_bypass = sample.hitRead && sample.p1Valid && sample.p1Tag == sample.s1Tag &&
            sample.p1Index == sample.s1Index && sample.p1Way == sample.hitWay && sample.p1WordOff == sample.s1WordOff;
        require_condition(sample.bypass === expected_bypass, "Bypass qualification differs from full address key");
        if (expected_bypass) begin
            require_condition(sample.hitReadData === sample.p1Data, "Bypass data does not match preceding write");
            count("bypass_used");
        end
        if (sample.hitRead && sample.p1Valid) begin
            if (sample.p1Tag != sample.s1Tag) count("bypass_reject_tag");
            if (sample.p1Index != sample.s1Index) count("bypass_reject_set");
            if (sample.p1Way != sample.hitWay) count("bypass_reject_way");
            if (sample.p1WordOff != sample.s1WordOff) count("bypass_reject_word");
        end
        if (sample.s1Valid && sample.s2Stuck) begin
            require_condition(sample.cache_r1_en && sample.cache_r1_index === sample.s1Index &&
                sample.cache_r1_wordOff === sample.s1WordOff, "Frozen request R1 refresh is missing or uses wrong address");
            count("frozen_r1_refresh");
            if (sample.respFullAny && cycle == accepted_at[sample.s1Id] + 1 &&
                previous != null && !previous.respFullAny) count("accepted_then_fifo_full");
            if (!freeze_active) begin
                freeze_active = 1;
                freeze_started = cycle;
            end
            if (sample.p1Valid) count("frozen_bypass_context");
        end else if (freeze_active) begin
            if (cycle-freeze_started > max_freeze) max_freeze = int'(cycle-freeze_started);
            count("freeze_recovered");
            if (expected_bypass) count("bypass_after_freeze");
            freeze_active = 0;
        end
        if (previous != null && previous.s1Valid && previous.s2Stuck) begin
            require_condition({sample.s1Tag,sample.s1Index,sample.s1WordOff,sample.s1Id,sample.s1WrEn,sample.s1WData} ===
                {previous.s1Tag,previous.s1Index,previous.s1WordOff,previous.s1Id,previous.s1WrEn,previous.s1WData}, "Stage2 request changed while frozen");
        end
    endfunction

    // 只按真实push/pop维护FIFO义务，核对顺序与载荷；不把RAM占用计数误当含输出级的总数。
    function void check_fifo_transfers(dcache_probe_sample sample);
        fifo_read_t item;
        int id;
        if (sample.rd_io_pop_valid && sample.rd_io_pop_ready) begin
            require_condition(fifo_read_records.size() > 0, "Read FIFO pop has no accepted push");
            if (fifo_read_records.size() > 0) begin
                item = fifo_read_records.pop_front();
                require_condition(sample.rd_io_pop_payload_id === item.id && sample.rd_io_pop_payload_rData === item.data,
                    "Read FIFO lost order or changed payload");
            end
        end
        if (sample.wr_io_pop_valid && sample.wr_io_pop_ready) begin
            require_condition(fifo_write_records.size() > 0, "Write FIFO pop has no accepted push");
            if (fifo_write_records.size() > 0) begin
                id = fifo_write_records.pop_front();
                require_condition(sample.wr_io_pop_payload_id === 5'(id), "Write FIFO lost order");
            end
        end
        if (sample.rd_io_push_valid && sample.rd_io_push_ready) begin
            item.id = sample.rd_io_push_payload_id;
            item.data = sample.rd_io_push_payload_rData;
            fifo_read_records.push_back(item);
        end
        if (sample.wr_io_push_valid && sample.wr_io_push_ready) fifo_write_records.push_back(sample.wr_io_push_payload_id);
        if (sample.rd_io_occupancy == 4 && sample.s1Valid && sample.s1WrEn) count("read_full_blocks_write_stage2");
        if (sample.wr_io_occupancy == 4 && sample.s1Valid && !sample.s1WrEn) count("write_full_blocks_read_stage2");
        if (sample.rd_io_occupancy == 4 && cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_payload_wrEn) begin
            require_condition(!cpu_vif.mon_cb.cpu_ready, "Read queue full must backpressure incoming write");
            count("read_full_blocks_write_cpu");
        end
        if (sample.wr_io_occupancy == 4 && cpu_vif.mon_cb.cpu_valid && !cpu_vif.mon_cb.cpu_payload_wrEn) begin
            require_condition(!cpu_vif.mon_cb.cpu_ready, "Write queue full must backpressure incoming read");
            count("write_full_blocks_read_cpu");
        end
        count_latency(sample);
    endfunction

    // 按CPU ID记录接受、提交、入队及最终响应时间，分开统计内部处理与CPU反压等待。
    function void count_latency(dcache_probe_sample sample);
        int delay_cycles;
        int id;
        if (sample.rd_io_pop_valid && sample.rd_io_pop_ready) begin
            id = sample.rd_io_pop_payload_id;
            delay_cycles = int'(cycle-enqueued_at[id]);
            if (!latency_enqueue_response.exists(delay_cycles)) latency_enqueue_response[delay_cycles] = 0;
            latency_enqueue_response[delay_cycles]++;
        end
        if (sample.wr_io_pop_valid && sample.wr_io_pop_ready) begin
            id = sample.wr_io_pop_payload_id;
            delay_cycles = int'(cycle-enqueued_at[id]);
            if (!latency_enqueue_response.exists(delay_cycles)) latency_enqueue_response[delay_cycles] = 0;
            latency_enqueue_response[delay_cycles]++;
        end
        if (sample.commit) begin
            id = sample.s1Id;
            committed_at[id] = cycle;
            delay_cycles = int'(cycle-accepted_at[id]);
            if (!latency_accept_commit.exists(delay_cycles)) latency_accept_commit[delay_cycles] = 0;
            latency_accept_commit[delay_cycles]++;
        end
        if (sample.rd_io_push_valid && sample.rd_io_push_ready) record_enqueue(sample.rd_io_push_payload_id);
        if (sample.wr_io_push_valid && sample.wr_io_push_ready) record_enqueue(sample.wr_io_push_payload_id);
        if (cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_ready) accepted_at[cpu_vif.mon_cb.cpu_payload_id] = cycle;
    endfunction

    // 一个ID的提交与入队可同拍，提交时间已先登记；不强加所有请求相同延迟。
    function void record_enqueue(int id);
        int delay_cycles;
        enqueued_at[id] = cycle;
        delay_cycles = int'(cycle-committed_at[id]);
        if (!latency_commit_enqueue.exists(delay_cycles)) latency_commit_enqueue[delay_cycles] = 0;
        latency_commit_enqueue[delay_cycles]++;
    endfunction

    // 记录存储端口并发和跨流水窗口，仅统计实际发生的条件。
    function void count_pipeline_windows(dcache_probe_sample sample);
        if (sample.cache_r1_en && sample.cache_r2_en) count("r1_r2_parallel");
        if (sample.cache_w1_en && sample.cache_w2_en) begin
            count("w1_w2_parallel");
            if (sample.cache_w1_way != sample.cache_w2_way) count("dual_write_different_way");
            if (sample.cache_r1_en) count("r1_w1_w2_parallel");
        end
        if (sample.cache_r1_en && sample.cache_r2_en && sample.cache_w2_en) count("r1_r2_w2_parallel");
        if (sample.cache_r1_en && sample.cache_r2_en && sample.cache_w1_en && sample.cache_w2_en) count("four_memory_ports");
        if (sample.cache_r1_en && sample.cache_r2_en && sample.cache_r1_index != sample.cache_r2_index) count("dual_read_different_set");
        if (previous != null) begin
            if (sample.cache_r2_en && previous.cache_r2_en && sample.cache_r2_way != previous.cache_r2_way) count("adjacent_r2_way_change");
            if (sample.w_reserve_en && sample.w_reserveOk && previous.w_reserve_en && previous.w_reserveOk) count("consecutive_dirty_evictions");
            if (previous.w_reserve_en && previous.w_reserveOk && wbb_vif.mon_cb.q0Same &&
                cpu_vif.mon_cb.cpu_payload_addr[31:6] == previous.w_reserve_addr[31:6]) count("reserved_address_query");
            if (sample.w_reserve_en && sample.w_reserveOk && sample.memWriteResp_valid && sample.memWriteResp_ready) count("reserve_and_write_ack");
            if (previous.cache_w2_en && sample.s1Valid && sample.s1Index == previous.cache_w2_index && sample.s1Tag == previous.cache_w2_tag)
                count("fill_during_request_pipeline");
        end
        if (sample.w_reserve_en && sample.w_reserveOk && sample.memWriteResp_valid && sample.memWriteResp_ready && writeback_outstanding == 3) count("last_wbb_with_ack");
        if (sample.w_reserve_en && sample.w_reserveOk) writeback_outstanding++;
        if (sample.memWriteResp_valid && sample.memWriteResp_ready) writeback_outstanding--;
        if (sample.cache_clr_en && sample.cache_inspect_dirty[sample.cache_clr_way]) count("clear_dirty_line");
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        foreach (hits[label]) begin
            `info($sformatf("%s=%0d", label, hits[label]), "DCACHE_INTERNAL_COVERAGE")
        end
        foreach (latency_accept_commit[delay_cycles]) begin
            `info($sformatf("accept_to_commit cycles=%0d count=%0d", delay_cycles, latency_accept_commit[delay_cycles]), "DCACHE_LATENCY_COVERAGE")
        end
        foreach (latency_commit_enqueue[delay_cycles]) begin
            `info($sformatf("commit_to_enqueue cycles=%0d count=%0d", delay_cycles, latency_commit_enqueue[delay_cycles]), "DCACHE_LATENCY_COVERAGE")
        end
        foreach (latency_enqueue_response[delay_cycles]) begin
            `info($sformatf("enqueue_to_response cycles=%0d count=%0d", delay_cycles, latency_enqueue_response[delay_cycles]), "DCACHE_LATENCY_COVERAGE")
        end
    endfunction

    function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        // dcache_fifo_destroy只释放独立原FIFO参考对象。
        dcache_fifo_destroy(policy_handle);
    endfunction

    // 只读全组tag/valid/dirty用于唯一性和未填充无效性检查；不读写RAM数据副本。
    function void check_metadata(dcache_probe_sample sample);
        int location;
        foreach (live[entry]) begin
            if (live[entry] && !entry_filled[entry]) begin
                location = int'(entry_set[entry])*4 + int'(entry_way[entry]);
                require_condition(sample.cache_valid_map[location] === 1'b0, "Unfilled Entry target is still valid");
                count("unfilled_invalid_checked");
            end
        end
        for (int set_index = 0; set_index < 32; set_index++) begin
            for (int first_way = 0; first_way < 4; first_way++) begin
                for (int second_way = first_way+1; second_way < 4; second_way++) begin
                    if (sample.cache_valid_map[set_index*4+first_way] && sample.cache_valid_map[set_index*4+second_way]) begin
                        require_condition(sample.cache_tag_map[(set_index*4+first_way)*21 +: 21] !==
                            sample.cache_tag_map[(set_index*4+second_way)*21 +: 21], "Two valid ways contain the same tag");
                        count("unique_valid_tags_checked");
                    end
                end
            end
        end
        if (cpu_vif.mon_cb.cpu_valid && mshr_vif.mon_cb.m0_hit &&
            entry_filled[mshr_vif.mon_cb.m0_entry]) count("filled_locked_cpu_query");
        if (previous != null && previous.cache_clr_en) begin
            location = int'(previous.cache_clr_index)*4 + int'(previous.cache_clr_way);
            require_condition(sample.cache_valid_map[location] === 1'b0, "CLR did not clear valid next cycle");
            require_condition(sample.cache_dirty_map[location] === previous.cache_dirty_map[location], "CLR changed dirty");
            if (sample.cache_dirty_map[location]) count("invalid_dirty_retained");
        end
    endfunction

    // 独立按架构公式检查CPU准入和R1使能，并记录Stage1估计到Stage2之间的实际变化。
    function void check_ready_and_windows(dcache_probe_sample sample);
        int active_entries;
        bit merge_allowed;
        bit available_way;
        bit expected_ready;
        bit [3:0] locked;
        locked = sample.m_lockMask[int'(cpu_vif.mon_cb.cpu_payload_addr[10:6])*4 +: 4];
        merge_allowed = mshr_vif.mon_cb.m0_hit && mshr_vif.mon_cb.m0_mergeable && mshr_vif.mon_cb.m0_slotFree;
        available_way = !(&locked);
        expected_ready = !sample.s2Stuck && !sample.respFullAny && (merge_allowed ||
            (!mshr_vif.mon_cb.m0_hit && sample.m_hasFree && !sample.w_full && !wbb_vif.mon_cb.q0Same && available_way));
        require_condition(cpu_vif.mon_cb.cpu_ready === expected_ready, "cpu.ready differs from specification resource formula");
        require_condition(sample.cache_r1_en === ((cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_ready) || sample.s2Stuck),
            "R1 enable differs from acceptance/refresh rule");
        if (!sample.cache_r1_en) count("r1_disabled_checked");
        if (merge_allowed && sample.w_full && cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_ready) count("merge_bypasses_wbb_full");
        if (previous_cpu_accept && sample.s1Valid) begin
            if (previous_m0_hit && previous_m0_mergeable && (!sample.m_m1_hit || !sample.m_m1_mergeable)) count("stage_merge_qualification_changed");
            if (!previous_m0_hit && sample.m_m1_hit) count("stage_new_entry_visible");
        end
        active_entries = 0;
        foreach (live[entry]) if (live[entry]) active_entries++;
        if (sample.m_alloc_en && sample.memReadResp_valid && sample.memReadResp_ready) begin
            count("alloc_with_response");
            if (active_entries == 3) count("last_entry_with_response");
        end
        if (sample.s1Valid && sample.s2Stuck && sample.w_full && sample.respFullAny) count("two_stall_causes");
        if (sample.s1Valid && sample.s2Stuck && sample.w_full && !sample.respFullAny && sample.victimDirty)
            count("dirty_wait_after_fifo_release");
        if (sample.s1Valid && sample.s2Stuck && !sample.m_hasFree) begin
            count("stage2_no_entry");
            if (&sample.m_lockMask[int'(sample.s1Index)*4 +: 4]) count("stage2_all_ways_locked");
        end
        if (previous_cpu_accept && released_previous_cycle && sample.m_alloc_en && int'(sample.m_freeEntry) == released_entry)
            count("accepted_then_entry_reused");
        released_previous_cycle = sample.m_replay_valid && sample.m_replay_ready &&
            returned_slots[cpu_entry[sample.m_replay_payload_id]] + 1 == slots[cpu_entry[sample.m_replay_payload_id]];
        if (released_previous_cycle) released_entry = cpu_entry[sample.m_replay_payload_id];
        previous_cpu_accept = cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_ready;
        previous_m0_hit = mshr_vif.mon_cb.m0_hit;
        previous_m0_mergeable = mshr_vif.mon_cb.m0_mergeable && mshr_vif.mon_cb.m0_slotFree;
        previous_m0_entry = mshr_vif.mon_cb.m0_entry;
    endfunction

    // 记录真实存储端口组合；地址/数据正确性仍由独立原C++ CacheMem检查。
    function void count_memory_combinations(dcache_probe_sample sample);
        int location;
        if (sample.cache_r1_en && sample.cache_r2_en) begin
            count($sformatf("dual_read_way_word_%0d_%0d", sample.cache_r2_way, sample.cache_r1_wordOff));
            count(sample.cache_r1_index == sample.cache_r2_index ? "dual_read_same_set" : "dual_read_other_set");
        end
        if (sample.cache_w1_en && sample.cache_w2_en) begin
            count($sformatf("dual_write_ways_%0d_%0d", sample.cache_w1_way, sample.cache_w2_way));
            count($sformatf("dual_write_bank_%0d_%0d", sample.cache_w1_way, sample.cache_w1_wordOff));
            count(sample.cache_w1_index == sample.cache_w2_index ? "dual_write_same_set" : "dual_write_other_set");
        end

        // 先观察读请求的沿前历史，再登记本拍写入，避免把同拍写碰撞算成写后读。
        if (sample.cache_r1_en) begin
            for (int way = 0; way < 4; way++) begin
                location = int'(sample.cache_r1_index)*4 + way;
                if (sample.cache_valid_map[location] && words_written_after_fill[location][sample.cache_r1_wordOff])
                    count($sformatf("w2_w1_r1_%0d_%0d", way, sample.cache_r1_wordOff));
            end
        end
        if (sample.cache_r2_en) begin
            location = int'(sample.cache_r2_index)*4 + int'(sample.cache_r2_way);
            for (int word_index = 0; word_index < 16; word_index++) begin
                if (words_written_after_fill[location][word_index])
                    count($sformatf("w2_w1_r2_%0d_%0d", sample.cache_r2_way, word_index));
            end
        end
        if (sample.cache_w2_en) begin
            location = int'(sample.cache_w2_index)*4 + int'(sample.cache_w2_way);
            filled_from_w2[location] = 1;
            words_written_after_fill[location] = '0;
        end
        if (sample.cache_w1_en) begin
            location = int'(sample.cache_w1_index)*4 + int'(sample.cache_w1_way);
            if (filled_from_w2[location]) words_written_after_fill[location][sample.cache_w1_wordOff] = 1;
        end
    endfunction

    // 从实际W1写入和CPU读接受记录同字碰撞；读提交时检查旁路及写值，冻结期间保留这笔义务。
    function void check_read_during_write(dcache_probe_sample sample);
        int cpu_id;
        cpu_id = sample.s1Id;
        if (sample.commit && same_edge_read_pending[cpu_id]) begin
            if (sample.hitRead) begin
                require_condition(sample.bypass === 1'b1, "Same-edge write/read did not select bypass");
                require_condition(sample.hitReadData === same_edge_write_data[cpu_id],
                    "Same-edge write/read did not return the accepted W1 value");
                count("same_edge_wr_checked");
                count_raw_read_value(sample, same_edge_write_data[cpu_id]);
            end
            same_edge_read_pending[cpu_id] = 0;
        end

        // 本沿前台写入与新读地址相同；R1使能和地址也必须确实指向这笔已接受读。
        if (cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_ready && !cpu_vif.mon_cb.cpu_payload_wrEn &&
            sample.cache_w1_en && sample.cache_r1_en &&
            cpu_vif.mon_cb.cpu_payload_addr[31:11] == sample.s1Tag &&
            cpu_vif.mon_cb.cpu_payload_addr[10:6] == sample.cache_w1_index &&
            cpu_vif.mon_cb.cpu_payload_addr[5:2] == sample.cache_w1_wordOff &&
            sample.cache_r1_index == sample.cache_w1_index && sample.cache_r1_wordOff == sample.cache_w1_wordOff) begin
            cpu_id = cpu_vif.mon_cb.cpu_payload_id;
            same_edge_read_pending[cpu_id] = 1;
            same_edge_write_data[cpu_id] = sample.cache_w1_data;
            count("same_edge_wr_observed");
            count($sformatf("same_edge_wr_way_word_%0d_%0d", sample.cache_w1_way, sample.cache_w1_wordOff));
            if (previous != null && previous.cache_w1_en && previous.s1Tag == sample.s1Tag &&
                previous.cache_w1_index == sample.cache_w1_index && previous.cache_w1_wordOff == sample.cache_w1_wordOff)
                count("same_edge_wr_after_two_writes");
        end
    endfunction

    // 仅记录原始R1数据与写值的关系；spec不限定RAM碰撞返回值，因此不强制某类结果出现。
    function void count_raw_read_value(dcache_probe_sample sample, logic [DATA_WIDTH-1:0] expected_write);
        logic [DATA_WIDTH-1:0] ram_value;
        case (sample.hitWay)
            0: ram_value = sample.cache_r1_data_0;
            1: ram_value = sample.cache_r1_data_1;
            2: ram_value = sample.cache_r1_data_2;
            3: ram_value = sample.cache_r1_data_3;
            default: ram_value = 'x;
        endcase
        if ($isunknown(ram_value)) begin
            count("same_edge_wr_raw_unknown");
        end else if (ram_value != expected_write) begin
            count("same_edge_wr_raw_differs");
        end else begin
            count("same_edge_wr_raw_same");
        end
    endfunction
