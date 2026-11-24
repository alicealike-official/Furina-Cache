// 同时准备多Entry、多Slot重放候选，放行后检查Entry间轮询以及各Entry内部Slot顺序。
class mshr_replay_arbitration_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_replay_arbitration_sequence)

    function new(string name = "mshr_replay_arbitration_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 同时准备多Entry、多Slot重放候选，放行后检查Entry间轮询以及各Entry内部Slot顺序。
task mshr_replay_arbitration_sequence::body();
    mshr_expected_line group[$];
    mshr_expected_line line;
    int release_start;

    required_rounds = 2;

    cfg.mem_response_enable = 0;
    cfg.replay_enable = 0;
    prepare_group(MSHR_ENTRIES, MSHR_MAX_PENDING, group);
    cfg.mem_response_enable = 1;
    obs.wait_count("fill", MSHR_ENTRIES);
    obs.wait_cycles(4);
    finish_round();
    // 第二轮各Entry使用不同Slot数，先释放Entry1/3，再服务稀疏的0/2候选。
    cfg.mem_response_enable = 0;
    group.delete();
    for (int entry_index = 0; entry_index < MSHR_ENTRIES; entry_index++) begin
        line = prepare_line(entry_index, entry_index);
        group.push_back(line);
        for (int slot_index = 0; slot_index <= entry_index; slot_index++) begin
            request_slot(line, bit'(slot_index % 2), slot_index, DATA_WIDTH'('h34560000 + slot_index));
        end
    end
    obs.wait_count("send", expected_alloc);
    release_start = obs.hits["release"];
    respond_entry(group[1].entry);
    obs.wait_count("release", release_start + 1);
    respond_entry(group[3].entry);
    obs.wait_count("release", release_start + 2);
    cfg.replay_enable = 0;
    respond_entry(group[0].entry);
    respond_entry(group[2].entry);
    obs.wait_count("fill", expected_alloc);
    obs.wait_cycles(4);
    finish_round();
    required_hits["replay_stall"] = 8;
endtask
