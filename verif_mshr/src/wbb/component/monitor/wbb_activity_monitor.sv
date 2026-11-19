// 只记录接口上已经发生的事件，供 sequence 安排后续动作、test 检查场景是否命中。
// 这里不预测 DUT 输出，也不替代已有 C++ WBB 模型和 IO 断言。
class wbb_activity_monitor extends uvm_subscriber #(wbb_sample);
    localparam int FREE = 0;
    localparam int RESERVED = 1;
    localparam int PENDING = 2;
    localparam int ISSUED = 3;
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
    int response_reorders = 0;
    int send_ids[$];
    int response_ids[$];
    int reserve_slots[$];
    longint unsigned send_cycles[$];
    longint unsigned response_cycles[$];
    protected int in_flight_ids[$];
    protected int send_burst = 0;
    protected int last_send_id = -1;

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

    tr = t;
    last_sample = tr;
    if (tr.rst_n !== 1'b1) begin
        return;
    end
    cycle++;
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
        reserve_count++;
    end
    if (tr.push_en && !$isunknown(tr.push_slot) && tr.push_slot < WBB_ENTRIES) begin
        slot = tr.push_slot;
        delay_cycles = int'(cycle - reserved_at[slot]);
        if (delay_cycles > 1) delayed_push_count++;
        if (delay_cycles > max_push_delay) max_push_delay = delay_cycles;
        loaded[slot] = 1;
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
