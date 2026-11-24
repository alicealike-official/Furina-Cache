// 高位Entry请求被反压时释放低位旧Entry并插入新请求，原挂起发送不得被抢占。
class mshr_send_backpressure_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_send_backpressure_sequence)

    function new(string name = "mshr_send_backpressure_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 高位Entry请求被反压时释放低位旧Entry并插入新请求，原挂起发送不得被抢占。
task mshr_send_backpressure_sequence::body();
    mshr_expected_line group[$];
    mshr_expected_line held_line;
    mshr_expected_line new_line;

    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES - 1, 1, group);
    obs.wait_count("send", MSHR_ENTRIES - 1);
    cfg.mem_request_enable = 0;
    held_line = prepare_line(MSHR_ENTRIES - 1, NUM_WAYS - 1);
    request_slot(held_line, 0, 0, 0);
    obs.wait_count("send_stall", 3);
    respond_entry(group[0].entry);
    obs.wait_count("release", 1);
    new_line = prepare_line(NUM_SETS - 1, 0);
    request_slot(new_line, 0, WORDS_PER_BLOCK - 1, 0);
    obs.wait_cycles(5);
    finish_round();
    required_hits["send_stall"] = 5;
    required_hits["send_new_candidate"] = 1;
endtask
