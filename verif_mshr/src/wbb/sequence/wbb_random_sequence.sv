// 每批使用N个互不相同的块地址，批间等待全部响应后再复用地址并更换随机数据。
class wbb_random_sequence extends wbb_scenario_sequence;
    localparam int BATCH_COUNT = 32;
    localparam int WRITEBACK_COUNT = BATCH_COUNT * WBB_ENTRIES;
    int completed_batches = 0;
    int randomized_lines = 0;

    `uvm_object_utils(wbb_random_sequence)

    function new(string name = "wbb_random_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task send_random_batch();
    extern task prime_stall_and_reordering();
endclass

task wbb_random_sequence::body();
    if (WBB_ENTRIES < 2) begin
        `fatal("Random reordering case requires at least two slots", "WBB_CASE_CONFIG")
    end
    prime_stall_and_reordering();
    for (int batch = 1; batch < BATCH_COUNT; batch++) begin
        send_random_batch();
        obs.wait_until_empty();
        completed_batches++;
    end
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
endtask

// 打乱本批地址顺序，随机化整行数据、两查询地址及事务间空闲拍数。
// 每个地址在一批中只使用一次；下一批开始前等待全空，因此不会向在途地址重复reserve。
task wbb_random_sequence::send_random_batch();
    int order[$];
    int unsigned gap;
    int unsigned q0_index;
    int unsigned q1_index;
    bit [LINE_WIDTH-1:0] line_data;

    for (int index = 0; index < WBB_ENTRIES; index++) begin
        order.push_back(index);
    end
    order.shuffle();
    foreach (order[index]) begin
        if (!std::randomize(line_data, gap, q0_index, q1_index) with {
            gap inside {[0:3]};
            q0_index inside {[0:WBB_ENTRIES+1]};
            q1_index inside {[0:WBB_ENTRIES+1]};
        }) begin
            `fatal("Failed to randomize WBB batch data and timing", "WBB_RANDOMIZE")
        end
        if (gap > 0) begin
            idle_cycles(gap);
        end
        send_data(block_addr(order[index]), line_data, block_addr(q0_index), block_addr(q1_index));
        randomized_lines++;
    end
endtask

// 第一批先保持send背压，再逆序响应实际已发送的ID，保证这次运行确实包含背压和乱序。
// 后续批次交由memory driver随机ready、随机延迟和随机选择到期响应。
task wbb_random_sequence::prime_stall_and_reordering();
    int send_start;

    send_start = obs.send_count;
    send_random_batch();
    obs.wait_cycles(3);
    cfg.mem_send_enable = 1;
    obs.wait_for_sends(send_start + WBB_ENTRIES);
    for (int index = WBB_ENTRIES - 1; index >= 0; index--) begin
        release_response(obs.send_ids[send_start + index]);
    end
    obs.wait_until_empty();
    completed_batches++;
    cfg.mem_response_order = WBB_MEM_RANDOM;
    cfg.mem_response_enable = 1;
endtask
