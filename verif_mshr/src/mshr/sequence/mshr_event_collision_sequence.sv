// 两条已发请求连续返回，使不同Entry的fill/replay重叠；精确merge边界由额外定向子场景补齐。
class mshr_event_collision_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_event_collision_sequence)

    function new(string name = "mshr_event_collision_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task fill_to_last_slot(mshr_expected_line line);
    extern task multi_events(bit allocate, bit send, bit fill, bit replay, bit merge_send = 0);
    extern task merge_with_response();
    extern task merge_with_send();
    extern task fill_with_replay();
    extern task allocate_with_response();
    extern task send_with_response();
    extern task release_with_allocation();

endclass

// 两条已发请求连续返回，使不同Entry的fill/replay重叠；精确merge边界由额外定向子场景补齐。
task mshr_event_collision_sequence::body();
    required_rounds = 12;

    merge_with_response();
    merge_with_send();
    fill_with_replay();
    allocate_with_response();
    send_with_response();
    release_with_allocation();

    // 三种四事件alloc组合；四个沿前/新分配Entry分别承担独立职责。
    multi_events(1, 1, 1, 0);
    multi_events(1, 1, 0, 1);
    multi_events(1, 0, 1, 1);
    // 五事件组合：merge分别作用于正在响应和正在发送的Entry。
    multi_events(0, 1, 1, 1, 0);
    multi_events(0, 1, 1, 1, 1);
    required_hits["multi_alloc_send_response_fill"] = 1;
    required_hits["multi_alloc_send_response_replay"] = 1;
    required_hits["multi_alloc_response_fill_replay"] = 1;
    required_hits["multi_merge_send_response_fill_replay"] = 2;
    required_hits["multi_merge_response_owner"] = 1;
    required_hits["multi_merge_send_owner"] = 1;
    required_hits["merge_response"] = 2;
    required_hits["merge_send"] = 1;
    required_hits["fill_replay"] = 1;
    required_hits["alloc_response"] = 1;
    required_hits["send_response"] = 1;
    required_hits["release_alloc"] = 1;
    required_hits["boundary_last_entry_response"] = 3;
    required_hits["boundary_last_entry_release"] = 1;
    required_hits["boundary_last_slot_response_read"] = 1;
    required_hits["boundary_last_slot_response_write"] = 1;
    required_hits["boundary_full_last_slot_five_events"] = 2;
    required_hits["boundary_full_release_recovery"] = 2;
endtask

// 最后Slot为读/写各运行一次，与该Entry响应同沿。
task mshr_event_collision_sequence::merge_with_response();
    mshr_expected_line line;

    for (int last_write = 0; last_write < 2; last_write++) begin
        cfg.mem_response_enable = 0;
        line = prepare_line(0, 0);
        request_slot(line, 0, 0, 0);
        request_slot(line, 1, 0, 'h12345678);
        request_slot(line, 0, 0, 0);
        obs.wait_count("send", expected_alloc);
        obs.wait_cycles(1);
        cfg.response_not_before_cycle = obs.cycle + 2;
        cfg.mem_response_enable = 1;
        request_slot(line, bit'(last_write), 0, 'h87654321);
        finish_round();
    end
endtask

// merge与首次读发送同沿，仍只发一次内存请求。
task mshr_event_collision_sequence::merge_with_send();
    mshr_expected_line line;

    cfg.mem_request_enable = 0;
    cfg.mem_response_enable = 0;
    line = prepare_line(0, 0);
    request_slot(line, 0, 0, 0);
    obs.wait_cycles(1);
    cfg.request_not_before_cycle = obs.cycle + 2;
    cfg.mem_request_enable = 1;
    request_slot(line, 1, WORDS_PER_BLOCK - 1, 'hface0001);
    finish_round();
endtask

// 连续不同Entry响应，检查随后不同Entry的fill与replay同拍。
task mshr_event_collision_sequence::fill_with_replay();
    mshr_expected_line group[$];

    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group);
    obs.wait_count("send", expected_alloc);
    finish_round();
endtask

// 接收旧Entry响应的同一沿分配新Entry，双方数据和锁应各自生效。
task mshr_event_collision_sequence::allocate_with_response();
    mshr_expected_line line;
    mshr_expected_line other_line;

    cfg.mem_response_enable = 0;
    line = prepare_line(0, 0);
    request_slot(line, 0, 0, 0);
    obs.wait_count("send", expected_alloc);
    obs.wait_cycles(1);
    other_line = prepare_line(1, 1);
    cfg.response_not_before_cycle = obs.cycle + 2;
    cfg.mem_response_enable = 1;
    request_slot(other_line, 1, 1, 'hface0002);
    finish_round();
endtask

// 新Entry读请求与旧Entry响应同沿；不构造同ID零拍响应。
task mshr_event_collision_sequence::send_with_response();
    mshr_expected_line line;
    mshr_expected_line other_line;

    cfg.mem_response_enable = 0;
    line = prepare_line(0, 0);
    request_slot(line, 0, 0, 0);
    obs.wait_count("send", expected_alloc);
    cfg.mem_request_enable = 0;
    other_line = prepare_line(1, 1);
    request_slot(other_line, 0, 1, 0);
    obs.wait_cycles(1);
    cfg.request_not_before_cycle = obs.cycle + 1;
    cfg.response_not_before_cycle = obs.cycle + 1;
    cfg.mem_request_enable = 1;
    cfg.mem_response_enable = 1;
    finish_round();
endtask

// 旧Entry的最后replay与另一空Entry的alloc同沿，不能误清新占用或锁。
task mshr_event_collision_sequence::release_with_allocation();
    mshr_expected_line line;
    mshr_expected_line other_line;

    cfg.replay_enable = 0;
    line = prepare_line(0, 0);
    request_slot(line, 0, 0, 0);
    obs.wait_count("fill", expected_alloc);
    obs.wait_cycles(1);
    other_line = prepare_line(1, 1);
    fork
        begin
            obs.wait_cycles(1);
            cfg.replay_enable = 1;
        end
        request_slot(other_line, 0, 1, 0);
    join
    finish_round();
endtask

// 按沿前生命周期准备独立Entry，再把单上游提交与各通道接受对齐到同一个上升沿。
// allocate分支最多四事件；五事件需要merge复用已有Entry，不构造第五个Entry或零拍响应。
task mshr_event_collision_sequence::multi_events(bit allocate, bit send, bit fill, bit replay, bit merge_send);
    mshr_expected_line replay_line;
    mshr_expected_line fill_line;
    mshr_expected_line response_line;
    mshr_expected_line send_line;
    mshr_expected_line allocated_line;
    int block_index;
    int fill_target;

    block_index = 0;
    cfg.mem_response_enable = 0;
    cfg.replay_enable = 0;
    if (replay) begin
        replay_line = prepare_line(block_index, block_index);
        block_index++;
        request_slot(replay_line, 0, 0, 0);
        obs.wait_count("send", expected_alloc);
        fill_target = obs.hits.exists("fill") ? obs.hits["fill"] + 1 : 1;
        respond_entry(replay_line.entry);
        obs.wait_count("fill", fill_target);
    end

    // 待fill行已经收到响应，但没有接受fill；下一条只等待响应。
    cfg.fill_enable = 0;
    if (fill) begin
        fill_line = prepare_line(block_index, block_index);
        block_index++;
        request_slot(fill_line, 1, 1, 'h13572468);
        obs.wait_count("send", expected_alloc);
        respond_entry(fill_line.entry);
    end
    response_line = prepare_line(block_index, block_index);
    block_index++;
    request_slot(response_line, 0, 2, 0);
    obs.wait_count("send", expected_alloc);

    // 发送候选保持到目标沿；alloc分支另准备一个沿前空Entry的新块。
    cfg.mem_request_enable = 0;
    if (send) begin
        send_line = prepare_line(block_index, block_index);
        block_index++;
        request_slot(send_line, 0, 3, 0);
    end
    // 五事件阶段先把目标填到仅剩最后一个Slot，最终merge恰好占满。
    if (!allocate) begin
        fill_to_last_slot(merge_send ? send_line : response_line);
    end
    if (allocate) allocated_line = prepare_line(block_index, block_index);
    obs.wait_cycles(1);
    cfg.mem_order = MSHR_MEM_SELECTED;
    cfg.selected_response_id = response_line.entry;
    cfg.response_not_before_cycle = obs.cycle + 2;
    cfg.request_not_before_cycle = obs.cycle + 2;
    cfg.mem_response_enable = 1;
    cfg.mem_request_enable = send;

    // driver的准备查询和资格判断用两个下降沿；在第二个下降沿统一放行sink。
    fork
        begin
            obs.wait_cycles(1);
            cfg.fill_enable = fill;
            cfg.replay_enable = replay;
        end
        begin
            if (allocate) begin
                request_slot(allocated_line, 1, 4, 'h24681357);
            end else if (merge_send) begin
                request_slot(send_line, 1, 3, 'h11223344);
            end else begin
                request_slot(response_line, 1, 2, 'h55667788);
            end
        end
    join
    finish_round();
endtask

// 只准备到剩一个空Slot，保留最后一次merge给目标并发沿；响应/发送仍由场景门控。
task mshr_event_collision_sequence::fill_to_last_slot(mshr_expected_line line);
    while (line.slot_count < MSHR_MAX_PENDING - 1) begin
        request_slot(line, 0, line.slot_count, 0);
    end
endtask
