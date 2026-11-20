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
        foreach (query_matrix[i, j]) begin
            query_matrix[i][j] = 0;
        end
    endfunction

    extern virtual function void write(wbb_sample t);
    extern function int address_stage(bit [ADDR_WIDTH-1:0] addr);
    extern function void record_queries(wbb_sample tr);
    extern function void record_events(wbb_sample tr);
    extern function void record_pipeline_events(wbb_sample tr, wbb_sample previous);
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
    wbb_sample tr;
    wbb_sample previous;

    previous = last_sample;
    tr = t;
    last_sample = tr;
    if (tr.rst_n !== 1'b1) begin
        return;
    end
    cycle++;
    record_pipeline_events(tr, previous);
    record_queries(tr);
    if ($countones(loaded & ~issued) > max_pending) begin
        max_pending = $countones(loaded & ~issued);
    end
    if ((&occupied) && loaded == '0 && tr.full === 1'b1) begin
        full_reserved_cycles++;
    end
    if (tr.send_valid === 1'b1 && tr.send_ready === 1'b0) begin
        send_stall_cycles++;
        if (tr.push_en === 1'b1 && tr.push_slot != tr.send_payload_id) begin
            stall_new_candidate_cycles++;
        end
    end
    if (tr.memWriteResp_valid && tr.memWriteResp_ready) begin
        if (tr.reserve_en && tr.reserveOk) reserve_response_cycles++;
        if (tr.push_en) push_response_cycles++;
        if (tr.send_valid && tr.send_ready) send_response_cycles++;
        if (tr.reserve_en && tr.reserveOk && tr.push_en) begin
            reserve_push_response_cycles++;
            if (tr.send_valid && tr.send_ready) begin
                reserve_push_send_response_cycles++;
            end
        end
    end
    record_events(tr);
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
function void wbb_activity_monitor::record_queries(wbb_sample tr);
    int stage0;
    int stage1;

    stage0 = address_stage(tr.q0Addr);
    stage1 = address_stage(tr.q1Addr);
    query_matrix[stage0][stage1]++;
    if (tr.q0Same && tr.q1Same) begin
        if (tr.q0Addr == tr.q1Addr) same_hit_cycles++;
        else different_hit_cycles++;
    end
    if (!tr.q0Same && !tr.q1Same) begin
        if (occupied != '0) query_none_while_occupied++;
        else empty_query_cycles++;
    end
endfunction

// 保存实际握手的槽号、顺序和拍数；响应完成时只移除对应的在途ID。
function void wbb_activity_monitor::record_events(wbb_sample tr);
    int slot;
    int delay_cycles;

    if (tr.reserve_en && tr.reserveOk && !$isunknown(tr.reserveSlot) && tr.reserveSlot < WBB_ENTRIES) begin
        slot = tr.reserveSlot;
        occupied[slot] = 1;
        slot_addr[slot] = tr.reserve_addr;
        reserved_at[slot] = cycle;
        reserve_uses[slot]++;
        reserve_slots.push_back(slot);
        reserve_cycles.push_back(cycle);
        reserve_samples.push_back(tr);
        reserve_count++;
    end
    if (tr.push_en && !$isunknown(tr.push_slot) && tr.push_slot < WBB_ENTRIES) begin
        slot = tr.push_slot;
        delay_cycles = int'(cycle - reserved_at[slot]);
        if (delay_cycles > 1) delayed_push_count++;
        if (delay_cycles > max_push_delay) max_push_delay = delay_cycles;
        loaded[slot] = 1;
        push_cycles.push_back(cycle);
        push_samples.push_back(tr);
        push_count++;
    end
    if (tr.send_valid && tr.send_ready && !$isunknown(tr.send_payload_id) && tr.send_payload_id < WBB_ENTRIES) begin
        slot = tr.send_payload_id;
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
    if (tr.memWriteResp_valid && tr.memWriteResp_ready && !$isunknown(tr.memWriteResp_payload_id) &&
        tr.memWriteResp_payload_id < WBB_ENTRIES) begin
        slot = tr.memWriteResp_payload_id;
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
function void wbb_activity_monitor::record_pipeline_events(wbb_sample tr, wbb_sample previous);
    if (tr.reserve_en === 1'b1 && tr.reserveOk === 1'b0) begin
        blocked_reserve_cycles++;
        waiting_for_overlap = 1;
        if (tr.push_en === 1'b1) begin
            blocked_push_cycles++;
        end
        if (tr.full === 1'b1 && tr.memWriteResp_valid === 1'b1 && tr.memWriteResp_ready === 1'b1) begin
            full_response_block_count++;
        end
    end
    if (tr.reserve_en === 1'b1 && tr.reserveOk === 1'b1 && tr.push_en === 1'b1) begin
        overlap_count++;
        if (waiting_for_overlap) begin
            resumed_overlap_count++;
            waiting_for_overlap = 0;
        end
    end
    if (tr.push_en === 1'b1 && tr.reserve_en === 1'b0) begin
        tail_push_count++;
        // 只有尾部push说明当前一段已结束，不能把旧停顿记到下一批的重叠上。
        waiting_for_overlap = 0;
    end else if (tr.reserve_en === 1'b0 && tr.push_en === 1'b0) begin
        // 失败的reserve也可以合法撤回；经过空闲后再开始新请求，不算原先停顿的流水恢复。
        waiting_for_overlap = 0;
    end
    if (previous != null && previous.rst_n === 1'b1 &&
        previous.full === 1'b1 && previous.reserve_en === 1'b1 && previous.reserveOk === 1'b0 &&
        previous.memWriteResp_valid === 1'b1 && previous.memWriteResp_ready === 1'b1 &&
        tr.full === 1'b0 && tr.reserve_en === 1'b1 && tr.reserveOk === 1'b1 &&
        tr.reserve_addr === previous.reserve_addr &&
        BUS_ID_WIDTH'(tr.reserveSlot) === previous.memWriteResp_payload_id) begin
        full_response_recovery_count++;
    end
endfunction

// 返回当前事件计数的值副本，供多阶段case在开始/结束时记录，再检查每段实际增加了多少次。
function wbb_activity_monitor::activity_snapshot_t wbb_activity_monitor::snapshot();
    activity_snapshot_t value;

    value.cycle = cycle;
    value.reserve_count = reserve_count;
    value.push_count = push_count;
    value.send_count = send_count;
    value.response_count = response_count;
    value.overlap_count = overlap_count;
    value.blocked_reserve_cycles = blocked_reserve_cycles;
    value.blocked_push_cycles = blocked_push_cycles;
    value.full_response_block_count = full_response_block_count;
    value.full_response_recovery_count = full_response_recovery_count;
    value.resumed_overlap_count = resumed_overlap_count;
    value.tail_push_count = tail_push_count;
    return value;
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
