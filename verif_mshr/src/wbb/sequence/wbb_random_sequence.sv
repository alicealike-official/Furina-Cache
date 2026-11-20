// 每批使用N个互不相同的块地址，批间等待全部响应后再复用地址并更换随机数据。
class wbb_random_sequence extends wbb_scenario_sequence;
    localparam int BATCH_COUNT = 32;
    localparam int WRITEBACK_COUNT = BATCH_COUNT * WBB_ENTRIES;
    int completed_batches = 0;
    int randomized_lines = 0;
    // 不含受控第一批，记录随机阶段实际出现的重叠及有重叠的批次数。
    int random_phase_overlaps = 0;
    int overlapping_random_batches = 0;

    `uvm_object_utils(wbb_random_sequence)

    function new(string name = "wbb_random_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task send_random_batch();
    extern task prime_stall_and_reordering();
endclass

task wbb_random_sequence::body();
    int overlap_before;

    if (WBB_ENTRIES < 2) begin
        `fatal("Random reordering case requires at least two slots", "WBB_CASE_CONFIG")
    end
    prime_stall_and_reordering();
    for (int batch = 1; batch < BATCH_COUNT; batch++) begin
        overlap_before = obs.overlap_count;
        send_random_batch();
        obs.wait_until_empty();
        random_phase_overlaps += obs.overlap_count - overlap_before;
        if (obs.overlap_count > overlap_before) begin
            overlapping_random_batches++;
        end
        completed_batches++;
    end
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
endtask

// 两种模式共用地址排列、整行数据和查询地址的随机生成。
// 串行模式保留每笔之前的随机空闲；流水模式把第一笔的gap用于整批之前，再连续提交本批N项。
// 每个地址在一批中只使用一次；下一批开始前等待全空，因此不会向在途地址重复reserve。
task wbb_random_sequence::send_random_batch();
    int order[$];
    wbb_transaction items[$];
    int unsigned batch_gap;
    int unsigned gap;
    int unsigned q0_index;
    int unsigned q1_index;
    bit [LINE_WIDTH-1:0] line_data;

    // 打乱本批地址顺序，保证每个块在排空前只被提交一次。
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        order.push_back(index);
    end
    order.shuffle();
    batch_gap = 0;

    // 为每笔生成数据、查询地址和空闲拍数；随机调用顺序保持一致。
    foreach (order[index]) begin
        if (!std::randomize(line_data, gap, q0_index, q1_index) with {
            gap inside {[0:3]};
            q0_index inside {[0:WBB_ENTRIES+1]};
            q1_index inside {[0:WBB_ENTRIES+1]};
        }) begin
            `fatal("Failed to randomize WBB batch data and timing", "WBB_RANDOMIZE")
        end

        // 流水模式先收集整批，串行模式在各笔之前插入对应空闲。
        if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
            wbb_transaction item;

            item = wbb_transaction::type_id::create($sformatf("random_item_%0d", index));
            item.addr = block_addr(order[index]);
            item.line_data = line_data;
            item.q0Addr = block_addr(q0_index);
            item.q1Addr = block_addr(q1_index);
            items.push_back(item);
            if (index == 0) begin
                batch_gap = gap;
            end
        end else begin
            idle_cycles(gap);
            send_data(block_addr(order[index]), line_data, block_addr(q0_index), block_addr(q1_index));
        end
        randomized_lines++;
    end

    // 整批构造完成后，再统一提交流水请求，避免重复登记原始数据。
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        idle_cycles(batch_gap);
        // send_group统一保存原始数据并提交流水批次，不能再逐笔调用send_data重复登记。
        send_group(items);
    end
endtask

// 第一批先保持send背压，再逆序响应实际已发送的ID，保证这次运行确实包含背压和乱序。
// 后续批次交由memory driver随机ready、随机延迟和随机选择到期响应。
task wbb_random_sequence::prime_stall_and_reordering();
    int send_start;

    // 先保持发送背压，随后放行并等待本批所有请求被接收。
    send_start = obs.send_count;
    send_random_batch();
    obs.wait_cycles(3);
    cfg.mem_send_enable = 1;
    obs.wait_for_sends(send_start + WBB_ENTRIES);

    // 按真实发送ID逆序响应，保证预热阶段确实发生乱序。
    for (int index = WBB_ENTRIES - 1; index >= 0; index--) begin
        release_response(obs.send_ids[send_start + index]);
    end
    obs.wait_until_empty();
    completed_batches++;

    // 预热完成后，把响应选择交给随机策略。
    cfg.mem_response_order = WBB_MEM_RANDOM;
    cfg.mem_response_enable = 1;
endtask
