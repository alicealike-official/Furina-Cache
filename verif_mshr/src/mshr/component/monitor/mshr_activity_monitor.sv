// 从MSHR公开IO累计实际事件和阶段；只供场景调度及覆盖计数，不预测数据或代替C++模型。
class mshr_activity_monitor extends uvm_subscriber #(mshr_sample);
    event sampled;
    mshr_sample last_sample;
    int cycle = 0;
    bit check_full_release_next;
    int hits[string];
    int slots[MSHR_ENTRIES];
    int completed[MSHR_ENTRIES];
    int stage[MSHR_ENTRIES];
    int uses[MSHR_ENTRIES];
    int cpu_entry[1 << CPU_ID_WIDTH];
    bit cpu_pending[1 << CPU_ID_WIDTH];
    int send_ids[$];
    int response_ids[$];
    int in_flight[$];
    int send_cycle[MSHR_ENTRIES];
    int latency_hits[int];
    int previous_response_cycle = -2;
    int cancelled_entries;
    bit filled[MSHR_ENTRIES];
    bit [TAG_WIDTH-1:0] tags[MSHR_ENTRIES];
    bit [INDEX_WIDTH-1:0] indices[MSHR_ENTRIES];
    int bypasses[MSHR_ENTRIES];
    mshr_sample events[$];
    int entry_slot_hits[MSHR_ENTRIES][MSHR_MAX_PENDING][2][2];

    `uvm_component_utils(mshr_activity_monitor)

    function new(string name = "mshr_activity_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void write(mshr_sample t);
    extern function void reset_history();
    extern function void record_events(mshr_sample sample);
    extern function void record_resource_boundaries(mshr_sample sample, int occupied_count);
    extern function void record_multi_events(mshr_sample sample);
    extern function void record_replay(mshr_sample sample);
    extern function void record_memory(mshr_sample sample);
    extern function void record_requests(mshr_sample sample);

    extern function void count_event(string name);
    extern function void check_replay_progress(mshr_sample sample);
    extern function void record_fill_stall(mshr_sample previous, mshr_sample current);
    extern function void trace_stall_change(mshr_sample previous, mshr_sample current);
    extern task wait_cycles(int count);
    extern task wait_count(string name, int target);
    extern task wait_empty();
endclass

// 累加命名场景计数；不存在的键先初始化，避免使用未定义的关联数组元素。
function void mshr_activity_monitor::count_event(string name);
    if (!hits.exists(name)) hits[name] = 0;
    hits[name]++;
endfunction

// 先记录沿前资源、查询和同拍组合，再更新由握手推导的生命周期。
function void mshr_activity_monitor::write(mshr_sample t);
    int live;

    trace_stall_change(last_sample, t);
    record_fill_stall(last_sample, t);
    last_sample = t;
    if (!t.rst_n) begin
        reset_history();
        return;
    end
    cycle++;
    live = 0;
    foreach (stage[entry]) if (stage[entry] != 0) live++;
    if (live == MSHR_ENTRIES) count_event("entry_full");
    if (t.memReadReq_valid && !t.memReadReq_ready) count_event("send_stall");
    if (t.fill_en && !t.fillReady) count_event("fill_stall");
    if (t.replay_valid && !t.replay_ready) count_event("replay_stall");
    if (t.memReadReq_valid && !t.memReadReq_ready && t.alloc_en) count_event("send_new_candidate");
    if (t.replay_valid && !t.replay_ready && t.fill_en && t.fillReady) count_event("replay_new_candidate");
    if (t.merge_en && t.memReadResp_valid && t.memReadResp_ready &&
        t.merge_entry == t.memReadResp_payload_id) count_event("merge_response");
    if (t.merge_en && t.memReadReq_valid && t.memReadReq_ready &&
        t.merge_entry == t.memReadReq_payload_id) count_event("merge_send");
    if (t.fill_en && t.fillReady && t.replay_valid && t.replay_ready) count_event("fill_replay");
    if (t.alloc_en && t.replay_valid && t.replay_ready &&
        completed[cpu_entry[t.replay_payload_id]] + 1 == slots[cpu_entry[t.replay_payload_id]]) begin
        count_event("release_alloc");
    end
    if (t.alloc_en && t.memReadResp_valid && t.memReadResp_ready) count_event("alloc_response");
    if (t.memReadReq_valid && t.memReadReq_ready && t.memReadResp_valid && t.memReadResp_ready)
        count_event("send_response");
    count_event($sformatf("query_%0d_%0d", t.m0_hit, t.m1_hit));
    if (t.m0_hit && t.m1_hit && t.m0_entry != t.m1_entry) count_event("query_different");
    if (t.m0_hit) count_event($sformatf("query_stage_%0d", stage[t.m0_entry]));
    if (t.m0_hit && t.m0_mergeable && !t.m0_slotFree) count_event("slot_full");
    for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
        if (&t.lockMask[set_index * NUM_WAYS +: NUM_WAYS]) count_event("all_ways_locked");
    end
    record_multi_events(t);
    record_resource_boundaries(t, live);
    check_replay_progress(t);
    record_events(t);
    ->sampled;
endfunction

// 保存实际事件、Entry/CPU ID归属及接受位置；不读取DUT寄存器。
function void mshr_activity_monitor::record_events(mshr_sample sample);
    if (sample.alloc_en || sample.merge_en || (sample.memReadReq_valid && sample.memReadReq_ready) ||
        (sample.memReadResp_valid && sample.memReadResp_ready) || (sample.fill_en && sample.fillReady) ||
        (sample.replay_valid && sample.replay_ready)) events.push_back(sample);
    record_replay(sample);
    record_memory(sample);
    record_requests(sample);
endfunction

// 等待完成指定拍数的沿前采样，返回点可安全修改下一拍配置。
task mshr_activity_monitor::wait_cycles(int count);
    repeat (count) @sampled;
endtask

// 等待实际接受事件到达目标数；所有等待受base test周期watchdog保护。
task mshr_activity_monitor::wait_count(string name, int target);
    while (!hits.exists(name) || hits[name] < target) @sampled;
endtask

// 依据实际分配与最后replay计数等待全空，不以参考模型状态替代实际完成。
task mshr_activity_monitor::wait_empty();
    wait_cycles(1);
    while (hits.exists("alloc") && (hits["alloc"] != (hits.exists("release") ? hits["release"] : 0) + cancelled_entries)) @sampled;
endtask

// 用已接受fill和Slot记录检查有限集合轮询上界，只计真实replay握手，不把反压拍数当饥饿。
function void mshr_activity_monitor::check_replay_progress(mshr_sample sample);
    int serviced_entry;

    if (!sample.replay_valid || !sample.replay_ready) return;
    serviced_entry = cpu_entry[sample.replay_payload_id];
    foreach (stage[entry]) begin
        if (stage[entry] != 0 && filled[entry] && completed[entry] < slots[entry]) begin
            if (entry == serviced_entry) begin
                bypasses[entry] = 0;
            end else begin
                bypasses[entry]++;
                if (bypasses[entry] >= MSHR_ENTRIES) begin
                    `error($sformatf("Eligible Entry %0d bypassed by %0d replay handshakes", entry,
                        bypasses[entry]), "MSHR_REPLAY_PROGRESS")
                end
            end
        end else begin
            bypasses[entry] = 0;
        end
    end
endfunction

// 当背压保持发生变化时打印相邻两拍的原始IO，用于定位归因；不修改断言或预测结果。
function void mshr_activity_monitor::trace_stall_change(mshr_sample previous, mshr_sample current);
    if (previous == null || !previous.rst_n || !current.rst_n) return;
    if (previous.replay_valid && !previous.replay_ready &&
        (current.replay_valid !== 1'b1 ||
        {current.replay_payload_isWrite, current.replay_payload_id, current.replay_payload_rData} !==
        {previous.replay_payload_isWrite, previous.replay_payload_id, previous.replay_payload_rData})) begin
        `info($sformatf("cycle=%0d previous(valid=%b ready=%b write=%b id=%0d data=%h fill=%b fillReady=%b fillTag=%h fillIndex=%0d) current(valid=%b ready=%b write=%b id=%0d data=%h)",
            cycle + 1, previous.replay_valid, previous.replay_ready, previous.replay_payload_isWrite,
            previous.replay_payload_id, previous.replay_payload_rData, previous.fill_en, previous.fillReady,
            previous.fill_tag, previous.fill_index, current.replay_valid, current.replay_ready,
            current.replay_payload_isWrite, current.replay_payload_id, current.replay_payload_rData), "MSHR_STALL_TRACE")
    end
endfunction

// 记录replay握手，最后Slot完成时才结束Entry生命周期。
function void mshr_activity_monitor::record_replay(mshr_sample sample);
    int entry;
    int cpu_id;

    if (sample.replay_valid && sample.replay_ready) begin
        cpu_id = sample.replay_payload_id;
        entry = cpu_entry[cpu_id];
        cpu_pending[cpu_id] = 0;
        completed[entry]++;
        count_event("replay");
        if (completed[entry] == slots[entry]) begin
            stage[entry] = 0;
            count_event("release");
        end
    end
endfunction

// 登记读请求/响应、实际延迟及fill接受，保留归属和乱序证据。
function void mshr_activity_monitor::record_memory(mshr_sample sample);
    int entry;
    int cpu_id;

    if (sample.memReadResp_valid && sample.memReadResp_ready) begin
        entry = sample.memReadResp_payload_id;
        stage[entry] = 3;
        if (cycle == previous_response_cycle + 1) count_event("adjacent_responses");
        previous_response_cycle = cycle;
        response_ids.push_back(entry);
        if (!latency_hits.exists(cycle - send_cycle[entry])) latency_hits[cycle - send_cycle[entry]] = 0;
        latency_hits[cycle - send_cycle[entry]]++;
        foreach (in_flight[index]) begin
            if (in_flight[index] == entry) begin
                if (index > 0) count_event("reorder");
                in_flight.delete(index);
                break;
            end
        end
        count_event("response");
    end
    if (sample.memReadReq_valid && sample.memReadReq_ready) begin
        entry = sample.memReadReq_payload_id;
        stage[entry] = 2;
        send_cycle[entry] = cycle;
        send_ids.push_back(entry);
        in_flight.push_back(entry);
        count_event("send");
    end
    if (sample.fill_en && sample.fillReady) begin
        count_event("fill");
        foreach (stage[index]) begin
            if (stage[index] != 0 && tags[index] == sample.fill_tag && indices[index] == sample.fill_index)
                filled[index] = 1;
        end
    end
endfunction

// 登记合法alloc/merge接受的位置、CPU ID及Entry/Slot/字位置覆盖。
function void mshr_activity_monitor::record_requests(mshr_sample sample);
    int entry;
    int cpu_id;

    if (sample.alloc_en) begin
        entry = sample.freeEntry;
        tags[entry] = sample.alloc_tag;
        indices[entry] = sample.alloc_index;
        filled[entry] = 0;
        bypasses[entry] = 0;
        slots[entry] = 1;
        completed[entry] = 0;
        stage[entry] = 1;
        uses[entry]++;
        cpu_id = sample.alloc_respId;
        cpu_entry[cpu_id] = entry;
        cpu_pending[cpu_id] = 1;
        entry_slot_hits[entry][0][sample.alloc_isWrite][sample.alloc_wordOff == WORDS_PER_BLOCK - 1]++;
        count_event("alloc");
    end
    if (sample.merge_en) begin
        entry = sample.merge_entry;
        entry_slot_hits[entry][slots[entry]][sample.merge_isWrite][sample.merge_wordOff == WORDS_PER_BLOCK - 1]++;
        slots[entry]++;
        cpu_id = sample.merge_respId;
        cpu_entry[cpu_id] = entry;
        cpu_pending[cpu_id] = 1;
        count_event("merge");
    end
endfunction

// 记录fill挂起时新响应及解除反压，并在输出变化时打印原始前后拍IO；不以模型选择裁决。
function void mshr_activity_monitor::record_fill_stall(mshr_sample previous, mshr_sample current);
    if (!current.rst_n) return;
    if (current.fill_en && !current.fillReady && current.memReadResp_valid && current.memReadResp_ready) begin
        count_event("fill_new_candidate");
        `info($sformatf("cycle=%0d held_tag=%h held_index=%0d held_way=%0d response_id=%0d",
            cycle + 1, current.fill_tag, current.fill_index, current.fill_way,
            current.memReadResp_payload_id), "MSHR_FILL_CANDIDATE")
    end
    if (previous == null || !previous.rst_n || !previous.fill_en || previous.fillReady) return;
    if (current.fill_en && current.fillReady) count_event("fill_stall_release");
    if (current.fill_en !== 1'b1 ||
        {previous.fill_tag, previous.fill_index, previous.fill_way, previous.fill_dirty, previous.fill_line} !==
        {current.fill_tag, current.fill_index, current.fill_way, current.fill_dirty, current.fill_line}) begin
        `info($sformatf("cycle=%0d previous(en=%b ready=%b tag=%h index=%0d way=%0d dirty=%b line=%h) current(en=%b ready=%b tag=%h index=%0d way=%0d dirty=%b line=%h)",
            cycle + 1, previous.fill_en, previous.fillReady, previous.fill_tag, previous.fill_index,
            previous.fill_way, previous.fill_dirty, previous.fill_line, current.fill_en, current.fillReady,
            current.fill_tag, current.fill_index, current.fill_way, current.fill_dirty, current.fill_line), "MSHR_FILL_STALL_TRACE")
    end
endfunction

// 只按同一沿的实际使能/握手统计多事件；五事件可同时证明其包含的合法三/四事件子组合。
function void mshr_activity_monitor::record_multi_events(mshr_sample sample);
    bit send_fire;
    bit response_fire;
    bit fill_fire;
    bit replay_fire;

    send_fire = sample.memReadReq_valid && sample.memReadReq_ready;
    response_fire = sample.memReadResp_valid && sample.memReadResp_ready;
    fill_fire = sample.fill_en && sample.fillReady;
    replay_fire = sample.replay_valid && sample.replay_ready;
    if (!response_fire) return;
    if (sample.alloc_en && send_fire && fill_fire) count_event("multi_alloc_send_response_fill");
    if (sample.alloc_en && send_fire && replay_fire) count_event("multi_alloc_send_response_replay");
    if (sample.alloc_en && fill_fire && replay_fire) count_event("multi_alloc_response_fill_replay");
    if (sample.merge_en && send_fire && fill_fire && replay_fire) begin
        count_event("multi_merge_send_response_fill_replay");
        if (sample.merge_entry == sample.memReadResp_payload_id) count_event("multi_merge_response_owner");
        if (sample.merge_entry == sample.memReadReq_payload_id) count_event("multi_merge_send_owner");
    end
endfunction

// 以沿前占用和Slot数记录临界组合；实际数据、锁及归属仍由公共检查器核对。
function void mshr_activity_monitor::record_resource_boundaries(mshr_sample sample, int occupied_count);
    bit response_fire;
    bit final_replay;
    int replay_entry;

    response_fire = sample.memReadResp_valid && sample.memReadResp_ready;
    replay_entry = sample.replay_valid ? cpu_entry[sample.replay_payload_id] : 0;
    final_replay = sample.replay_valid && sample.replay_ready &&
        completed[replay_entry] + 1 == slots[replay_entry];

    // 满表释放沿之后的下一采样沿必须能看到空Entry；不要求同沿旁路分配。
    if (check_full_release_next) begin
        if (sample.hasFree !== 1'b1) begin
            `error("Full-table final replay did not expose a free Entry next cycle", "MSHR_BOUNDARY_RECOVERY")
        end else begin
            count_event("boundary_full_release_recovery");
        end
    end
    check_full_release_next = occupied_count == MSHR_ENTRIES && final_replay;
    if (check_full_release_next) count_event("boundary_full_release");

    // 最后空Entry与后台事件同拍，或全满时仍向旧Entry追加合法Slot。
    if (sample.alloc_en && occupied_count == MSHR_ENTRIES - 1 && response_fire)
        count_event("boundary_last_entry_response");
    if (sample.alloc_en && occupied_count == MSHR_ENTRIES - 1 && final_replay)
        count_event("boundary_last_entry_release");
    if (sample.merge_en && occupied_count == MSHR_ENTRIES)
        count_event("boundary_full_merge");

    // 最后Slot分别在SEND和MISS_WAIT追加，并区分同Entry响应时的读/写请求。
    if (sample.merge_en && slots[sample.merge_entry] == MSHR_MAX_PENDING - 1) begin
        count_event($sformatf("boundary_last_slot_stage_%0d", stage[sample.merge_entry]));
        if (response_fire && sample.merge_entry == sample.memReadResp_payload_id) begin
            count_event(sample.merge_isWrite ? "boundary_last_slot_response_write" : "boundary_last_slot_response_read");
        end
        if (occupied_count == MSHR_ENTRIES && response_fire && sample.memReadReq_valid &&
            sample.memReadReq_ready && sample.fill_en && sample.fillReady && final_replay) begin
            count_event("boundary_full_last_slot_five_events");
        end
    end
endfunction

// 取消本轮接口归属，保留累计命中；复位不能清除之前已报告的协议错误。
function void mshr_activity_monitor::reset_history();
    foreach (stage[entry]) begin
        if (stage[entry] != 0) cancelled_entries++;
        stage[entry] = 0;
        slots[entry] = 0;
        completed[entry] = 0;
        filled[entry] = 0;
        bypasses[entry] = 0;
    end
    foreach (cpu_pending[id]) cpu_pending[id] = 0;
    in_flight.delete();
    check_full_release_next = 0;
    previous_response_cycle = -2;
    last_sample = null;
endfunction
