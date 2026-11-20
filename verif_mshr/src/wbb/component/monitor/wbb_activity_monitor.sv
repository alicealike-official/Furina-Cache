// 只记录接口上已经发生的事件，供 sequence 安排后续动作、test 检查场景是否命中。
// 这里不预测 DUT 输出，也不替代已有 C++ WBB 模型和 IO 断言。
class wbb_activity_monitor extends uvm_subscriber #(wbb_sample);
    localparam int FREE = 0;
    localparam int RESERVED = 1;
    localparam int PENDING = 2;
    localparam int ISSUED = 3;
    typedef struct packed {
        longint unsigned cycle;
        int reserve_count;
        int push_count;
        int send_count;
        int response_count;
        int overlap_count;
        int blocked_reserve_cycles;
        int blocked_push_cycles;
        int full_response_block_count;
        int full_response_recovery_count;
        int resumed_overlap_count;
        int tail_push_count;
    } activity_snapshot_t;
    event sampled;
    wbb_sample last_sample;
    longint unsigned cycle = 0;
    int reserve_count = 0;
    int push_count = 0;
    int send_count = 0;
    int response_count = 0;
    bit [WBB_ENTRIES-1:0] occupied = '0;
    bit [WBB_ENTRIES-1:0] loaded = '0;
    bit [WBB_ENTRIES-1:0] issued = '0;
    bit [ADDR_WIDTH-1:0] slot_addr[WBB_ENTRIES];
    longint unsigned reserved_at[WBB_ENTRIES];
    int reserve_uses[WBB_ENTRIES] = '{default: 0};
    int query_matrix[4][4];
    int same_hit_cycles = 0;
    int different_hit_cycles = 0;
    int query_none_while_occupied = 0;
    int empty_query_cycles = 0;
    int max_pending = 0;
    int full_reserved_cycles = 0;
    int delayed_push_count = 0;
    int max_push_delay = 0;
    int send_stall_cycles = 0;
    int stall_new_candidate_cycles = 0;
    int max_send_burst = 0;
    int rr_wrap_count = 0;
    int reserve_response_cycles = 0;
    int push_response_cycles = 0;
    int send_response_cycles = 0;
    int reserve_push_response_cycles = 0;
    int reserve_push_send_response_cycles = 0;
    int response_reorders = 0;
    int overlap_count = 0;
    int blocked_reserve_cycles = 0;
    int blocked_push_cycles = 0;
    int full_response_block_count = 0;
    int full_response_recovery_count = 0;
    int resumed_overlap_count = 0;
    int tail_push_count = 0;
    int send_ids[$];
    int response_ids[$];
    int reserve_slots[$];
    longint unsigned send_cycles[$];
    longint unsigned response_cycles[$];
    longint unsigned reserve_cycles[$];
    longint unsigned push_cycles[$];
    // monitor每拍发布独立对象；这些只读记录用于核对某笔reserve与随后push的槽号、数据和查询来源。
    wbb_sample reserve_samples[$];
    wbb_sample push_samples[$];
    protected int in_flight_ids[$];
    protected int send_burst = 0;
    protected int last_send_id = -1;
    protected bit waiting_for_overlap = 0;

    `uvm_component_utils(wbb_activity_monitor)

    function new(string name = "wbb_activity_monitor", uvm_component parent = null);
        super.new(name, parent);
        foreach (query_matrix[q0_stage, q1_stage]) begin
            query_matrix[q0_stage][q1_stage] = 0;
        end
    endfunction

    extern virtual function void write(wbb_sample t);
    extern function int address_stage(bit [ADDR_WIDTH-1:0] addr);
    extern function void record_queries(wbb_sample sample);
    extern function void record_events(wbb_sample sample);
    extern function void record_pipeline_events(wbb_sample sample, wbb_sample previous_sample);
    extern function activity_snapshot_t snapshot();
    extern task wait_cycles(int count);
    extern task wait_for_sends(int target);
    extern task wait_for_responses(int target);
    extern task wait_for_reserves(int target);
    extern task wait_for_pushes(int target);
    extern task wait_until_empty();
endclass

// 先按沿前历史统计场景，再登记本拍事件；最后通知等待这些事件的 sequence。
function void wbb_activity_monitor::write(wbb_sample t);
    wbb_sample sample;
    wbb_sample previous_sample;

    // 保留前后两拍样本，用于检测满槽释放后的恢复。
    previous_sample = last_sample;
    // t是uvm_subscriber::write规定的形参名，保留以匹配基类接口。
    sample = t;
    last_sample = sample;
    if (sample.rst_n !== 1'b1) begin
        return;
    end

    // 按沿前状态统计流水/查询和资源占用，不先修改槽历史。
    cycle++;
    record_pipeline_events(sample, previous_sample);
    record_queries(sample);
    if ($countones(loaded & ~issued) > max_pending) begin
        max_pending = $countones(loaded & ~issued);
    end
    if ((&occupied) && loaded == '0 && sample.full === 1'b1) begin
        full_reserved_cycles++;
    end

    // 记录真实发送背压，以及背压期间新push的候选。
    if (sample.send_valid === 1'b1 && sample.send_ready === 1'b0) begin
        send_stall_cycles++;
        if (sample.push_en === 1'b1 && sample.push_slot != sample.send_payload_id) begin
            stall_new_candidate_cycles++;
        end
    end

    // 统计响应与reserve、push、send在同一采样沿发生的组合。
    if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
        if (sample.reserve_en && sample.reserveOk) reserve_response_cycles++;
        if (sample.push_en) push_response_cycles++;
        if (sample.send_valid && sample.send_ready) send_response_cycles++;
        if (sample.reserve_en && sample.reserveOk && sample.push_en) begin
            reserve_push_response_cycles++;
            if (sample.send_valid && sample.send_ready) begin
                reserve_push_send_response_cycles++;
            end
        end
    end

    // 覆盖统计结束后才更新事件历史，并唤醒等待中的sequence。
    record_events(sample);
    ->sampled;
endfunction

// 根据已经接受的 reserve/push/send/response，返回某块地址当前所处阶段。
// 只用于场景分类；查询输出是否正确由已有 scoreboard 和 SVA 检查。
function int wbb_activity_monitor::address_stage(bit [ADDR_WIDTH-1:0] addr);
    for (int slot = 0; slot < WBB_ENTRIES; slot++) begin
        if (occupied[slot] && slot_addr[slot] == addr) begin
            if (issued[slot]) return ISSUED;
            if (loaded[slot]) return PENDING;
            return RESERVED;
        end
    end
    return FREE;
endfunction

// 记录两查询口在不同阶段的组合，另统计同址命中、异址双命中和非空时双不命中。
function void wbb_activity_monitor::record_queries(wbb_sample sample);
    int q0_stage;
    int q1_stage;

    q0_stage = address_stage(sample.q0Addr);
    q1_stage = address_stage(sample.q1Addr);
    query_matrix[q0_stage][q1_stage]++;
    if (sample.q0Same && sample.q1Same) begin
        if (sample.q0Addr == sample.q1Addr) same_hit_cycles++;
        else different_hit_cycles++;
    end
    if (!sample.q0Same && !sample.q1Same) begin
        if (occupied != '0) query_none_while_occupied++;
        else empty_query_cycles++;
    end
endfunction

// 保存实际握手的槽号、顺序和拍数；响应完成时只移除对应的在途ID。
function void wbb_activity_monitor::record_events(wbb_sample sample);
    int slot;
    int delay_cycles;

    // 登记成功reserve的地址、槽号和采样拍。
    if (sample.reserve_en && sample.reserveOk && !$isunknown(sample.reserveSlot) && sample.reserveSlot < WBB_ENTRIES) begin
        slot = sample.reserveSlot;
        occupied[slot] = 1;
        slot_addr[slot] = sample.reserve_addr;
        reserved_at[slot] = cycle;
        reserve_uses[slot]++;
        reserve_slots.push_back(slot);
        reserve_cycles.push_back(cycle);
        reserve_samples.push_back(sample);
        reserve_count++;
    end

    // 登记push及预留到push的间隔，槽从reserved进入待发阶段。
    if (sample.push_en && !$isunknown(sample.push_slot) && sample.push_slot < WBB_ENTRIES) begin
        slot = sample.push_slot;
        delay_cycles = int'(cycle - reserved_at[slot]);
        if (delay_cycles > 1) delayed_push_count++;
        if (delay_cycles > max_push_delay) max_push_delay = delay_cycles;
        loaded[slot] = 1;
        push_cycles.push_back(cycle);
        push_samples.push_back(sample);
        push_count++;
    end

    // 登记发送ID、连续发送长度和轮询回绕；发送不释放占用。
    if (sample.send_valid && sample.send_ready && !$isunknown(sample.send_payload_id) && sample.send_payload_id < WBB_ENTRIES) begin
        slot = sample.send_payload_id;
        issued[slot] = 1;
        send_ids.push_back(slot);
        send_cycles.push_back(cycle);
        in_flight_ids.push_back(slot);
        send_count++;
        send_burst++;
        if (send_burst > max_send_burst) max_send_burst = send_burst;
        if (last_send_id == WBB_ENTRIES - 1 && slot == 0) rr_wrap_count++;
        last_send_id = slot;
    end else begin
        send_burst = 0;
    end

    // 按实际响应ID移除在途记录，并释放对应槽。
    if (sample.memWriteResp_valid && sample.memWriteResp_ready && !$isunknown(sample.memWriteResp_payload_id) &&
        sample.memWriteResp_payload_id < WBB_ENTRIES) begin
        slot = sample.memWriteResp_payload_id;
        for (int index = 0; index < in_flight_ids.size(); index++) begin
            if (in_flight_ids[index] == slot) begin
                if (index > 0) response_reorders++;
                in_flight_ids.delete(index);
                break;
            end
        end
        occupied[slot] = 0;
        loaded[slot] = 0;
        issued[slot] = 0;
        response_ids.push_back(slot);
        response_cycles.push_back(cycle);
        response_count++;
    end
endfunction

// 记录流水重叠、预留被阻塞时仍完成push，以及满槽响应后的下一拍恢复。
// 这些只是场景计数；槽归属、输出数据和时序是否符合规格仍由原模型及SVA检查。
function void wbb_activity_monitor::record_pipeline_events(wbb_sample sample, wbb_sample previous_sample);

    // 记录预留阻塞时旧push仍完成，以及满槽当拍接受响应的情况。
    if (sample.reserve_en === 1'b1 && sample.reserveOk === 1'b0) begin
        blocked_reserve_cycles++;
        waiting_for_overlap = 1;
        if (sample.push_en === 1'b1) begin
            blocked_push_cycles++;
        end
        if (sample.full === 1'b1 && sample.memWriteResp_valid === 1'b1 && sample.memWriteResp_ready === 1'b1) begin
            full_response_block_count++;
        end
    end

    // 记录实际reserve/push重叠；曾阻塞的批次在此确认恢复。
    if (sample.reserve_en === 1'b1 && sample.reserveOk === 1'b1 && sample.push_en === 1'b1) begin
        overlap_count++;
        if (waiting_for_overlap) begin
            resumed_overlap_count++;
            waiting_for_overlap = 0;
        end
    end

    // 尾部push或空闲表示该段结束，清除跨批次的恢复等待标记。
    if (sample.push_en === 1'b1 && sample.reserve_en === 1'b0) begin
        tail_push_count++;
        // 只有尾部push说明当前一段已结束，不能把旧停顿记到下一批的重叠上。
        waiting_for_overlap = 0;
    end else if (sample.reserve_en === 1'b0 && sample.push_en === 1'b0) begin
        // 失败的reserve也可以合法撤回；经过空闲后再开始新请求，不算原先停顿的流水恢复。
        waiting_for_overlap = 0;
    end

    // 检查满槽响应后的下一拍，同一等待地址使用刚释放槽成功预留。
    if (previous_sample != null && previous_sample.rst_n === 1'b1 &&
        previous_sample.full === 1'b1 && previous_sample.reserve_en === 1'b1 && previous_sample.reserveOk === 1'b0 &&
        previous_sample.memWriteResp_valid === 1'b1 && previous_sample.memWriteResp_ready === 1'b1 &&
        sample.full === 1'b0 && sample.reserve_en === 1'b1 && sample.reserveOk === 1'b1 &&
        sample.reserve_addr === previous_sample.reserve_addr &&
        BUS_ID_WIDTH'(sample.reserveSlot) === previous_sample.memWriteResp_payload_id) begin
        full_response_recovery_count++;
    end
endfunction

// 返回当前事件计数的值副本，供多阶段case在开始/结束时记录，再检查每段实际增加了多少次。
function wbb_activity_monitor::activity_snapshot_t wbb_activity_monitor::snapshot();
    activity_snapshot_t counters;

    counters.cycle = cycle;
    counters.reserve_count = reserve_count;
    counters.push_count = push_count;
    counters.send_count = send_count;
    counters.response_count = response_count;
    counters.overlap_count = overlap_count;
    counters.blocked_reserve_cycles = blocked_reserve_cycles;
    counters.blocked_push_cycles = blocked_push_cycles;
    counters.full_response_block_count = full_response_block_count;
    counters.full_response_recovery_count = full_response_recovery_count;
    counters.resumed_overlap_count = resumed_overlap_count;
    counters.tail_push_count = tail_push_count;
    return counters;
endfunction

// 等待指定数量的已完成采样拍；返回点在上升沿之后，可安全准备下一下降沿使用的配置。
task wbb_activity_monitor::wait_cycles(int count);
    repeat (count) @sampled;
endtask

// 等待实际发送握手达到目标数，等待受 test 的总周期超时保护。
task wbb_activity_monitor::wait_for_sends(int target);
    while (send_count < target) @sampled;
endtask

// 等待实际响应握手达到目标数，不以响应valid单独作为完成依据。
task wbb_activity_monitor::wait_for_responses(int target);
    while (response_count < target) @sampled;
endtask

// 等待实际成功预留达到目标数，供需要与后续push对齐的场景使用。
task wbb_activity_monitor::wait_for_reserves(int target);
    while (reserve_count < target) @sampled;
endtask

// 等待实际push达到目标数，供安排后续内存放行时机使用。
task wbb_activity_monitor::wait_for_pushes(int target);
    while (push_count < target) @sampled;
endtask

// 等待已接受的写回全部收到响应；只观察接口事件，不读取DUT内部状态。
task wbb_activity_monitor::wait_until_empty();
    while (occupied != '0 || send_count != response_count) @sampled;
endtask
