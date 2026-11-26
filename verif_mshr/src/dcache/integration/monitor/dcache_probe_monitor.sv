// 沿前快照只采样真实接口；检查与覆盖在同一观察器中按固定顺序执行，避免analysis调用顺序竞争。
class dcache_probe_monitor extends uvm_component;
    virtual dcache_probe_interface vif;
    // IP字段直接读取复用接口的沿前clocking值，不再在顶层probe重映射一套端口。
    virtual mshr_interface mshr_vif;
    virtual wbb_interface wbb_vif;
    virtual dcache_interface cpu_vif;
    typedef struct packed {
        bit [31:0] addr;
        bit is_write;
        bit [31:0] data;
        bit [4:0] id;
    } accepted_cpu_t;
    accepted_cpu_t cpu_requests[$];
    int hits[string];
    longint unsigned cycle;
    longint unsigned accepted_at[32];
    longint unsigned committed_at[32];
    longint unsigned enqueued_at[32];
    longint unsigned freeze_started;
    int max_freeze;
    bit freeze_active;
    int fifo_read_ids[$];
    int fifo_write_ids[$];
    chandle policy_handle;
    bit live[4];
    bit entry_filled[4];
    int slots[4];
    int returned_slots[4];
    int cpu_entry[32];
    bit [4:0] entry_set[4];
    bit [1:0] entry_way[4];
    bit [20:0] entry_tag[4];
    dcache_probe_sample previous;
    dcache_probe_sample last_sample;
    event sampled;
    `uvm_component_utils(dcache_probe_monitor)
    function new(string name = "dcache_probe_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // DPI创建原RefModel/Cache/ReplacePolicy.hpp的独立FIFO策略，非SV重写算法。
        policy_handle = dcache_fifo_create();
        if (policy_handle == null) `fatal(dcache_last_error(), "DCACHE_POLICY_DPI")
        // 【防御性检查】CPU接口与内部接口使用同一沿前采样，避免异步analysis回调排序依赖。
        if (!uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", cpu_vif)) begin
            `fatal("CPU observation interface missing", "DCACHE_PROBE_CONFIG")
        end
        // 【防御性检查】集成monitor与IP monitor共用真实只读接口，各自不驱动信号。
        if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", mshr_vif) ||
            !uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", wbb_vif)) begin
            `fatal("Shared IP interfaces missing", "DCACHE_PROBE_CONFIG")
        end
        // 【防御性检查】探针case必须实际接入bind，不能默认为全零。
        if (!uvm_config_db #(virtual dcache_probe_interface)::get(this, "", "dcache_probe_vif", vif)) begin
            `fatal("Probe interface is not bound", "DCACHE_PROBE_CONFIG")
        end
    endfunction
    task run_phase(uvm_phase phase);
        forever begin
            dcache_probe_sample sample;
            @(vif.mon_cb);
            if (vif.mon_cb.connected !== 1'b1) begin
                `fatal("Probe disconnected", "DCACHE_PROBE_CONFIG")
            end
            sample = dcache_probe_sample::type_id::create("sample");
            sample.rst_n = vif.mon_cb.rst_n;

            // MSHR接口：由复用interface取得，与独立IP模型看到同一沿前输入。
            sample.m_alloc_en = mshr_vif.mon_cb.alloc_en;
            sample.m_alloc_tag = mshr_vif.mon_cb.alloc_tag;
            sample.m_alloc_index = mshr_vif.mon_cb.alloc_index;
            sample.m_alloc_way = mshr_vif.mon_cb.alloc_way;
            sample.m_alloc_respId = mshr_vif.mon_cb.alloc_respId;
            sample.m_alloc_hasWb = mshr_vif.mon_cb.alloc_hasWb;
            sample.m_alloc_wbSlot = mshr_vif.mon_cb.alloc_wbSlot;
            sample.m_merge_en = mshr_vif.mon_cb.merge_en;
            sample.m_merge_entry = mshr_vif.mon_cb.merge_entry;
            sample.m_merge_respId = mshr_vif.mon_cb.merge_respId;
            sample.m_hasFree = mshr_vif.mon_cb.hasFree;
            sample.m_freeEntry = mshr_vif.mon_cb.freeEntry;
            sample.m_m1_hit = mshr_vif.mon_cb.m1_hit;
            sample.m_m1_slotFree = mshr_vif.mon_cb.m1_slotFree;
            sample.m_m1_mergeable = mshr_vif.mon_cb.m1_mergeable;
            sample.m_m1_freeSlot = mshr_vif.mon_cb.m1_freeSlot;
            sample.m_fill_en = mshr_vif.mon_cb.fill_en;
            sample.m_fillReady = mshr_vif.mon_cb.fillReady;
            sample.m_fill_index = mshr_vif.mon_cb.fill_index;
            sample.m_fill_way = mshr_vif.mon_cb.fill_way;
            sample.m_fill_tag = mshr_vif.mon_cb.fill_tag;
            sample.m_fill_dirty = mshr_vif.mon_cb.fill_dirty;
            sample.m_fill_line = mshr_vif.mon_cb.fill_line;
            sample.m_replay_valid = mshr_vif.mon_cb.replay_valid;
            sample.m_replay_ready = mshr_vif.mon_cb.replay_ready;
            sample.m_replay_payload_id = mshr_vif.mon_cb.replay_payload_id;
            sample.m_replay_payload_isWrite = mshr_vif.mon_cb.replay_payload_isWrite;
            sample.m_replay_payload_rData = mshr_vif.mon_cb.replay_payload_rData;
            sample.m_lockMask = mshr_vif.mon_cb.lockMask;

            // WBB接口：只采样，不创建上游driver。
            sample.w_reserve_en = wbb_vif.mon_cb.reserve_en;
            sample.w_reserveOk = wbb_vif.mon_cb.reserveOk;
            sample.w_reserveSlot = wbb_vif.mon_cb.reserveSlot;
            sample.w_reserve_addr = wbb_vif.mon_cb.reserve_addr;
            sample.w_push_en = wbb_vif.mon_cb.push_en;
            sample.w_push_slot = wbb_vif.mon_cb.push_slot;
            sample.w_push_line = wbb_vif.mon_cb.push_line;
            sample.w_full = wbb_vif.mon_cb.full;

            // CacheMem接口：用于跨模块接线与淘汰交接检查。
            sample.cache_r2_en = vif.mon_cb.cache_r2_en;
            sample.cache_r2_index = vif.mon_cb.cache_r2_index;
            sample.cache_r2_way = vif.mon_cb.cache_r2_way;
            sample.cache_r2_line = vif.mon_cb.cache_r2_line;
            sample.cache_clr_en = vif.mon_cb.cache_clr_en;
            sample.cache_clr_index = vif.mon_cb.cache_clr_index;
            sample.cache_clr_way = vif.mon_cb.cache_clr_way;
            sample.cache_w2_en = vif.mon_cb.cache_w2_en;
            sample.cache_w2_index = vif.mon_cb.cache_w2_index;
            sample.cache_w2_way = vif.mon_cb.cache_w2_way;
            sample.cache_w2_tag = vif.mon_cb.cache_w2_tag;
            sample.cache_w2_dirty = vif.mon_cb.cache_w2_dirty;
            sample.cache_w2_line = vif.mon_cb.cache_w2_line;

            // 响应FIFO接口：用于来源仲裁与实际入队检查。
            sample.rd_io_push_valid = vif.mon_cb.rd_io_push_valid;
            sample.rd_io_push_ready = vif.mon_cb.rd_io_push_ready;
            sample.rd_io_push_payload_id = vif.mon_cb.rd_io_push_payload_id;
            sample.rd_io_pop_valid = vif.mon_cb.rd_io_pop_valid;
            sample.rd_io_pop_ready = vif.mon_cb.rd_io_pop_ready;
            sample.rd_io_pop_payload_id = vif.mon_cb.rd_io_pop_payload_id;
            sample.rd_io_occupancy = vif.mon_cb.rd_io_occupancy;
            sample.wr_io_push_valid = vif.mon_cb.wr_io_push_valid;
            sample.wr_io_push_ready = vif.mon_cb.wr_io_push_ready;
            sample.wr_io_push_payload_id = vif.mon_cb.wr_io_push_payload_id;
            sample.wr_io_pop_valid = vif.mon_cb.wr_io_pop_valid;
            sample.wr_io_pop_ready = vif.mon_cb.wr_io_pop_ready;
            sample.wr_io_pop_payload_id = vif.mon_cb.wr_io_pop_payload_id;
            sample.wr_io_occupancy = vif.mon_cb.wr_io_occupancy;
            sample.rd_io_push_payload_rData = vif.mon_cb.rd_io_push_payload_rData;
            sample.rd_io_pop_payload_rData = vif.mon_cb.rd_io_pop_payload_rData;

            // 顶层提交控制：用于关联命中来源及冻结状态。
            sample.hitRead = vif.mon_cb.hitRead;
            sample.hitWrite = vif.mon_cb.hitWrite;
            sample.hitReadData = vif.mon_cb.hitReadData;
            sample.hitWay = vif.mon_cb.hitWay;
            sample.s1Index = vif.mon_cb.s1Index;
            sample.s1Id = vif.mon_cb.s1Id;
            sample.s1Valid = vif.mon_cb.s1Valid;
            sample.s2Stuck = vif.mon_cb.s2Stuck;
            sample.commit = vif.mon_cb.commit;
            sample.memReadResp_valid = mshr_vif.mon_cb.memReadResp_valid;
            sample.memReadResp_ready = mshr_vif.mon_cb.memReadResp_ready;
            sample.memReadResp_payload_id = mshr_vif.mon_cb.memReadResp_payload_id;
            sample.memWriteResp_valid = wbb_vif.mon_cb.memWriteResp_valid;
            sample.memWriteResp_ready = wbb_vif.mon_cb.memWriteResp_ready;
            sample.memWriteResp_payload_id = wbb_vif.mon_cb.memWriteResp_payload_id;
            // CacheMem和旁路/策略接口用于新增的周期关联，未读取DE行为逻辑。
            sample.cache_r1_en = vif.mon_cb.cache_r1_en;
            sample.cache_r1_index = vif.mon_cb.cache_r1_index;
            sample.cache_r1_wordOff = vif.mon_cb.cache_r1_wordOff;
            sample.cache_w1_en = vif.mon_cb.cache_w1_en;
            sample.cache_w1_index = vif.mon_cb.cache_w1_index;
            sample.cache_w1_way = vif.mon_cb.cache_w1_way;
            sample.cache_w1_wordOff = vif.mon_cb.cache_w1_wordOff;
            sample.cache_w1_data = vif.mon_cb.cache_w1_data;
            sample.cache_inspect_index = vif.mon_cb.cache_inspect_index;
            sample.cache_inspect_valid = vif.mon_cb.cache_inspect_valid;
            sample.cache_inspect_dirty = vif.mon_cb.cache_inspect_dirty;
            sample.cache_r1_tag_0 = vif.mon_cb.cache_r1_tag_0;
            sample.cache_r1_valid_0 = vif.mon_cb.cache_r1_valid_0;
            sample.cache_r1_dirty_0 = vif.mon_cb.cache_r1_dirty_0;
            sample.cache_r1_data_0 = vif.mon_cb.cache_r1_data_0;
            sample.cache_r1_tag_1 = vif.mon_cb.cache_r1_tag_1;
            sample.cache_r1_valid_1 = vif.mon_cb.cache_r1_valid_1;
            sample.cache_r1_dirty_1 = vif.mon_cb.cache_r1_dirty_1;
            sample.cache_r1_data_1 = vif.mon_cb.cache_r1_data_1;
            sample.cache_r1_tag_2 = vif.mon_cb.cache_r1_tag_2;
            sample.cache_r1_valid_2 = vif.mon_cb.cache_r1_valid_2;
            sample.cache_r1_dirty_2 = vif.mon_cb.cache_r1_dirty_2;
            sample.cache_r1_data_2 = vif.mon_cb.cache_r1_data_2;
            sample.cache_r1_tag_3 = vif.mon_cb.cache_r1_tag_3;
            sample.cache_r1_valid_3 = vif.mon_cb.cache_r1_valid_3;
            sample.cache_r1_dirty_3 = vif.mon_cb.cache_r1_dirty_3;
            sample.cache_r1_data_3 = vif.mon_cb.cache_r1_data_3;
            sample.s1Tag = vif.mon_cb.s1Tag;
            sample.s1WordOff = vif.mon_cb.s1WordOff;
            sample.s1WrEn = vif.mon_cb.s1WrEn;
            sample.s1WData = vif.mon_cb.s1WData;
            sample.p1Valid = vif.mon_cb.p1Valid;
            sample.p1Tag = vif.mon_cb.p1Tag;
            sample.p1Index = vif.mon_cb.p1Index;
            sample.p1Way = vif.mon_cb.p1Way;
            sample.p1WordOff = vif.mon_cb.p1WordOff;
            sample.p1Data = vif.mon_cb.p1Data;
            sample.bypass = vif.mon_cb.bypass;
            sample.canMerge0 = vif.mon_cb.canMerge0;
            sample.canMerge1 = vif.mon_cb.canMerge1;
            sample.hasVictim = vif.mon_cb.hasVictim;
            sample.respFullAny = vif.mon_cb.respFullAny;
            sample.evictDirty = vif.mon_cb.evictDirty;
            sample.victimDirty = vif.mon_cb.victimDirty;
            sample.policyWay = vif.mon_cb.policyWay;
            sample.fifo_order = vif.mon_cb.fifo_order;
            sample.cache_valid_map = vif.mon_cb.cache_valid_map;
            sample.cache_dirty_map = vif.mon_cb.cache_dirty_map;
            sample.cache_tag_map = vif.mon_cb.cache_tag_map;
            if (!sample.rst_n) begin
                reset_history();
            end else begin
                cycle++;
                sample.cycle = cycle;
                validate_sample(sample);
                extended_checks(sample);
                check_cpu_submission(sample);
                check_locks(sample);
                check_response_paths(sample);
                check_eviction(sample);
                record_boundaries(sample);
                record_lifecycle(sample);
                previous = sample;
                last_sample = sample;
                ->sampled;
            end
        end
    endtask
    // 【防御性检查】映射到的控制及有效载荷必须已知，错误接线不得被当成未命中覆盖。
    function void validate_sample(dcache_probe_sample sample);
        if ($isunknown({sample.m_alloc_en,sample.m_merge_en,sample.m_hasFree,sample.m_fill_en,
            sample.m_fillReady,sample.m_replay_valid,sample.m_replay_ready,sample.m_lockMask,
            sample.w_reserve_en,sample.w_reserveOk,sample.w_push_en,sample.w_full,
            sample.rd_io_push_valid,sample.rd_io_push_ready,sample.wr_io_push_valid,sample.wr_io_push_ready,
            sample.rd_io_occupancy,sample.wr_io_occupancy,sample.hitRead,sample.hitWrite,sample.commit,sample.s2Stuck}) ||
            (sample.m_alloc_en && $isunknown({sample.m_freeEntry,sample.m_alloc_index,sample.m_alloc_way,sample.m_alloc_tag,sample.m_alloc_respId})) ||
            (sample.m_merge_en && $isunknown({sample.m_merge_entry,sample.m_merge_respId})) ||
            (sample.m_replay_valid && $isunknown({sample.m_replay_payload_id,sample.m_replay_payload_isWrite}))) begin
            `fatal("Unknown probe control or valid ownership field", "DCACHE_PROBE_X")
        end
    endfunction
    // 统一统计真实事件；检查器和sequence都不写DUT或探针信号。
    function void count(string label);
        if (!hits.exists(label)) hits[label] = 0;
        hits[label]++;
    endfunction
    // 检查条件失败时带采样周期报错，保留原DUT行为供诊断。
    function void require_condition(bit condition, string message);
        if (!condition) begin
            `error($sformatf("cycle=%0d %s", cycle, message), "DCACHE_INTEGRATION")
        end
    endfunction
    // 根据实际alloc和最后replay重建锁，不读取或预测内部状态编码。
    function void check_locks(dcache_probe_sample sample);
        bit [127:0] expected;
        int occupied_count;
        expected = '0;
        occupied_count = 0;
        foreach (live[entry]) begin
            if (live[entry]) begin
                expected[int'(entry_set[entry])*4 + int'(entry_way[entry])] = 1;
                occupied_count++;
            end
        end
        if (sample.m_alloc_en) begin
            require_condition(!expected[int'(sample.m_alloc_index)*4+int'(sample.m_alloc_way)], "alloc selects locked way");
        end
        if (sample.hitRead || sample.hitWrite) begin
            require_condition(!expected[int'(sample.s1Index)*4+int'(sample.hitWay)], "hit commits to locked way");
        end
        for (int set_index = 0; set_index < 32; set_index++) begin
            if (&expected[set_index*4 +: 4]) count("all_ways_locked");
        end
        if (sample.s1Valid && sample.s2Stuck && (&sample.m_lockMask[int'(sample.s1Index)*4 +: 4])) count("locked_set_wait");
        if (sample.m_fill_en && sample.m_fillReady) count("fill_while_locked");
    endfunction
    // 命中响应与replay竞争时检查优先级和被选载荷，FIFO push为接受事件而非CPU最终完成。
    function void check_response_paths(dcache_probe_sample sample);
        if (sample.hitRead) begin
            require_condition(sample.rd_io_push_valid && sample.rd_io_push_ready &&
                sample.rd_io_push_payload_id === sample.s1Id &&
                sample.rd_io_push_payload_rData === sample.hitReadData, "read hit not enqueued correctly");
        end
        if (sample.hitWrite) begin
            require_condition(sample.wr_io_push_valid && sample.wr_io_push_ready &&
                sample.wr_io_push_payload_id === sample.s1Id, "write hit not enqueued correctly");
        end
        if (sample.m_replay_valid) begin
            if ((sample.hitRead && !sample.m_replay_payload_isWrite) ||
                (sample.hitWrite && sample.m_replay_payload_isWrite)) begin
                count(sample.m_replay_payload_isWrite ? "write_priority" : "read_priority");
                require_condition(!sample.m_replay_ready, "same-type replay advanced while hit won");
            end
            if (sample.m_replay_ready) begin
                if (sample.m_replay_payload_isWrite) begin
                    require_condition(sample.wr_io_push_valid && sample.wr_io_push_ready &&
                        sample.wr_io_push_payload_id === sample.m_replay_payload_id, "write replay not enqueued");
                    if (sample.hitRead) count("hit_read_replay_write");
                end else begin
                    require_condition(sample.rd_io_push_valid && sample.rd_io_push_ready &&
                        sample.rd_io_push_payload_id === sample.m_replay_payload_id &&
                        sample.rd_io_push_payload_rData === sample.m_replay_payload_rData, "read replay not enqueued");
                    if (sample.hitWrite) count("hit_write_replay_read");
                end
            end
        end
        if (sample.rd_io_occupancy == 4) count("read_fifo_full");
        if (sample.wr_io_occupancy == 4) count("write_fifo_full");
    endfunction
    // 核对fill到Cache写口的同沿数据，以及脏淘汰预留、读行、清valid和下一拍push关联。
    function void check_eviction(dcache_probe_sample sample);
        require_condition(sample.cache_w2_en === (sample.m_fill_en && sample.m_fillReady), "fill and W2 acceptance differ");
        if (sample.cache_w2_en) begin
            require_condition({sample.cache_w2_index,sample.cache_w2_way,sample.cache_w2_tag,sample.cache_w2_dirty,sample.cache_w2_line} ===
                {sample.m_fill_index,sample.m_fill_way,sample.m_fill_tag,sample.m_fill_dirty,sample.m_fill_line}, "fill payload changed before CacheMem");
        end
        if (sample.m_alloc_en && sample.m_alloc_hasWb) begin
            require_condition(sample.w_reserve_en && sample.w_reserveOk && sample.cache_r2_en && sample.cache_clr_en &&
                sample.m_alloc_wbSlot === sample.w_reserveSlot && sample.cache_clr_index === sample.m_alloc_index &&
                sample.cache_clr_way === sample.m_alloc_way && sample.cache_r2_index === sample.m_alloc_index &&
                sample.cache_r2_way === sample.m_alloc_way, "dirty eviction actions not atomic");
            count("dirty_atomic");
        end
        if (previous != null && previous.w_reserve_en && previous.w_reserveOk) begin
            require_condition(sample.w_push_en && sample.w_push_slot === previous.w_reserveSlot &&
                sample.w_push_line === sample.cache_r2_line, "reserve-to-push association broken");
            count("reserve_push");
        end
    endfunction
    // 以沿前记录和实际接口识别资源最后位置、全满和释放同拍，不从CPU ready反推内部原因。
    function void record_boundaries(dcache_probe_sample sample);
        int occupied_count;
        occupied_count = 0;
        foreach (live[entry]) if (live[entry]) occupied_count++;
        if (sample.m_alloc_en && occupied_count == 3) count("last_entry_alloc");
        if (sample.m_merge_en && occupied_count == 4) count("full_entry_merge");
        if (sample.m_merge_en && slots[sample.m_merge_entry] == 3) begin
            count("last_slot_merge");
            if (sample.memReadResp_valid && sample.memReadResp_ready &&
                sample.memReadResp_payload_id == sample.m_merge_entry) count("last_slot_response");
        end
        if (sample.w_full && sample.memWriteResp_valid && sample.memWriteResp_ready) count("full_wbb_response");
        if (sample.m_replay_valid && sample.m_replay_ready &&
            returned_slots[cpu_entry[sample.m_replay_payload_id]] + 1 == slots[cpu_entry[sample.m_replay_payload_id]]) begin
            count("entry_release");
            if (occupied_count == 4) count("full_entry_release");
        end
    endfunction
    // 所有检查完成后才登记本沿的释放/分配/追加，保持统一沿前语义。
    function void record_lifecycle(dcache_probe_sample sample);
        int entry;
        if (sample.m_fill_en && sample.m_fillReady) begin
            foreach (live[index]) begin
                if (live[index] && entry_set[index] == sample.m_fill_index && entry_way[index] == sample.m_fill_way)
                    entry_filled[index] = 1;
            end
        end
        if (sample.m_replay_valid && sample.m_replay_ready) begin
            entry = cpu_entry[sample.m_replay_payload_id];
            returned_slots[entry]++;
            if (returned_slots[entry] == slots[entry]) live[entry] = 0;
        end
        if (sample.m_alloc_en) begin
            entry = sample.m_freeEntry;
            live[entry] = 1;
            entry_filled[entry] = 0;
            entry_set[entry] = sample.m_alloc_index;
            entry_way[entry] = sample.m_alloc_way;
            entry_tag[entry] = sample.m_alloc_tag;
            slots[entry] = 1;
            returned_slots[entry] = 0;
            cpu_entry[sample.m_alloc_respId] = entry;
            count("alloc");
        end
        if (sample.m_merge_en) begin
            slots[sample.m_merge_entry]++;
            cpu_entry[sample.m_merge_respId] = sample.m_merge_entry;
            count("merge");
        end
    endfunction
    // 先核对旧Stage2提交，再登记本沿新CPU请求；提交字段必须属于按顺序接受的原请求。
    function void check_cpu_submission(dcache_probe_sample sample);
        accepted_cpu_t request;
        if (sample.commit) begin
            require_condition(cpu_requests.size() != 0, "Stage2 commit has no accepted CPU request");
            if (cpu_requests.size() != 0) begin
                request = cpu_requests.pop_front();
                require_condition(sample.s1Id === request.id && sample.s1Index === request.addr[10:6], "Stage2 CPU identity changed");
                require_condition($countones({sample.m_alloc_en,sample.m_merge_en,sample.hitRead,sample.hitWrite}) == 1,
                    "CPU commit must take exactly one hit/alloc/merge path");
                if (sample.m_alloc_en) check_alloc_payload(request);
                if (sample.m_merge_en) check_merge_payload(request);
                if (sample.hitRead || sample.hitWrite) begin
                    require_condition(sample.hitWrite === request.is_write, "Hit response type differs from CPU request");
                end
                count("cpu_commit_checked");
            end
        end
        if (sample.s1Valid && sample.s2Stuck) begin
            require_condition(!sample.m_alloc_en && !sample.m_merge_en && !sample.hitRead && !sample.hitWrite &&
                !sample.cache_clr_en && !sample.cache_r2_en && !sample.w_reserve_en, "Frozen CPU request still performs commit actions");
            count("frozen_commit_suppressed");
        end
        if (cpu_vif.mon_cb.cpu_valid && cpu_vif.mon_cb.cpu_ready) begin
            request.addr = cpu_vif.mon_cb.cpu_payload_addr;
            request.is_write = cpu_vif.mon_cb.cpu_payload_wrEn;
            request.data = cpu_vif.mon_cb.cpu_payload_wData;
            request.id = cpu_vif.mon_cb.cpu_payload_id;
            cpu_requests.push_back(request);
        end
    endfunction
    // alloc的块地址、字位置、类型和CPU ID逐字段对应原请求；读请求不比较无意义写数据。
    function void check_alloc_payload(accepted_cpu_t request);
        require_condition(mshr_vif.mon_cb.alloc_tag === request.addr[31:11] &&
            mshr_vif.mon_cb.alloc_index === request.addr[10:6] &&
            mshr_vif.mon_cb.alloc_wordOff === request.addr[5:2] &&
            mshr_vif.mon_cb.alloc_respId === request.id &&
            mshr_vif.mon_cb.alloc_isWrite === request.is_write &&
            (!request.is_write || mshr_vif.mon_cb.alloc_wData === request.data), "CPU-to-alloc payload mismatch");
    endfunction
    // merge没有地址字段，按实际Entry分配历史确认目标块，再核对Slot内容。
    function void check_merge_payload(accepted_cpu_t request);
        int entry;
        entry = mshr_vif.mon_cb.merge_entry;
        require_condition(live[entry] && entry_tag[entry] === request.addr[31:11] &&
            entry_set[entry] === request.addr[10:6] && mshr_vif.mon_cb.merge_wordOff === request.addr[5:2] &&
            mshr_vif.mon_cb.merge_respId === request.id && mshr_vif.mon_cb.merge_isWrite === request.is_write &&
            (!request.is_write || mshr_vif.mon_cb.merge_wData === request.data), "CPU-to-merge payload mismatch");
    endfunction
    // 清理上一复位区间的集成义务；通过原C++ FIFO DPI重置策略对象，保留累计覆盖。
    function void reset_history();
        bit [255:0] unused_order;
        int unused_candidate;
        if (!dcache_fifo_step(policy_handle, 1, 0, 0, 0, 0, 0, 0,
            0, 0, 0, unused_candidate, unused_order)) begin
            `fatal(dcache_last_error(), "DCACHE_POLICY_DPI")
        end
        cpu_requests.delete();
        fifo_read_ids.delete();
        fifo_write_ids.delete();
        fifo_read_records.delete();
        fifo_write_records.delete();
        foreach (live[entry]) begin
            live[entry] = 0;
            entry_filled[entry] = 0;
            slots[entry] = 0;
            returned_slots[entry] = 0;
        end
        foreach (same_edge_read_pending[id]) same_edge_read_pending[id] = 0;
        foreach (filled_from_w2[location]) begin
            filled_from_w2[location] = 0;
            words_written_after_fill[location] = '0;
        end
        writeback_outstanding = 0;
        previous_cpu_accept = 0;
        released_previous_cycle = 0;
        freeze_active = 0;
        previous = null;
        last_sample = null;
    endfunction
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (fifo_read_records.size() != 0 || fifo_write_records.size() != 0) begin
            `error("Internal FIFO push/pop obligations did not drain", "DCACHE_FIFO_DRAIN")
        end
        if (cpu_requests.size() != 0) begin
            `error("Accepted CPU requests remain uncommitted", "DCACHE_INTEGRATION_DRAIN")
        end
    endfunction
    `include "integration/monitor/dcache_extended_checks.svh"
endclass
