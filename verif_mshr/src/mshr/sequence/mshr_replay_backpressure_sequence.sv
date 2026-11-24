// 分别阻塞读/写的首、中、末Slot，再构造挂起replay期间新增更靠前候选的场景。
class mshr_replay_backpressure_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_replay_backpressure_sequence)

    function new(string name = "mshr_replay_backpressure_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task hold_slot(bit is_write, int target_slot);
    extern task insert_candidate();
endclass

task mshr_replay_backpressure_sequence::body();
    required_rounds = 7;
    for (int write_kind = 0; write_kind < 2; write_kind++) begin
        hold_slot(bit'(write_kind), 0);
        hold_slot(bit'(write_kind), 1);
        hold_slot(bit'(write_kind), MSHR_MAX_PENDING - 1);
    end
    insert_candidate();
    required_hits["replay_stall"] = 6 * 4 + 8;
    required_hits["replay_new_candidate"] = 1;
endtask

// 暂停目标Slot的接受四拍；此前Slot正常完成，不能把首Slot的阻塞当作中末Slot覆盖。
task mshr_replay_backpressure_sequence::hold_slot(bit is_write, int target_slot);
    mshr_expected_line line;
    int replay_start;
    int stall_start;

    cfg.mem_response_enable = 0;
    cfg.replay_enable = 0;
    replay_start = obs.hits.exists("replay") ? obs.hits["replay"] : 0;
    stall_start = obs.hits.exists("replay_stall") ? obs.hits["replay_stall"] : 0;
    line = prepare_line(0, 0);
    for (int slot_index = 0; slot_index < MSHR_MAX_PENDING; slot_index++) begin
        request_slot(line, is_write, slot_index, DATA_WIDTH'('h23450000 + slot_index));
    end
    cfg.mem_response_enable = 1;
    obs.wait_count("fill", expected_alloc);
    if (target_slot > 0) begin
        cfg.replay_enable = 1;
        obs.wait_count("replay", replay_start + target_slot);
        cfg.replay_enable = 0;
        // 排除放行前首Slot可能已经产生的阻塞拍，单独统计当前目标。
        stall_start = obs.hits.exists("replay_stall") ? obs.hits["replay_stall"] : 0;
    end
    obs.wait_count("replay_stall", stall_start + 4);
    finish_round();
endtask

// 先服务最高Entry建立轮询起点0，再让该Entry的新事务挂起，低Entry完成fill后不得抢占。
task mshr_replay_backpressure_sequence::insert_candidate();
    mshr_expected_line group[$];
    mshr_expected_line held_line;
    int release_target;
    int stall_start;
    int fill_target;

    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group);
    obs.wait_count("send", expected_alloc);
    release_target = obs.hits["release"] + 1;
    respond_entry(group[MSHR_ENTRIES - 1].entry);
    obs.wait_count("release", release_target);

    // 只释放了最高Entry；新块只能分配到这一空位，不依赖后门读取轮询指针。
    cfg.replay_enable = 0;
    held_line = prepare_line(NUM_SETS - 1, NUM_WAYS - 1);
    request_slot(held_line, 0, 0, 0);
    obs.wait_count("send", expected_alloc);
    stall_start = obs.hits["replay_stall"];
    respond_entry(held_line.entry);
    obs.wait_count("replay_stall", stall_start + 4);

    // 旧replay仍被反压时让Entry0成为新候选，继续阻塞四拍再统一放行。
    fill_target = obs.hits["fill"] + 1;
    respond_entry(group[0].entry);
    obs.wait_count("fill", fill_target);
    obs.wait_cycles(4);
    finish_round();
endtask
