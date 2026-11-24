// 检查单候选阻塞，以及旧fill挂起期间另一Entry响应到达时的保持与恢复。
class mshr_fill_backpressure_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_fill_backpressure_sequence)

    function new(string name = "mshr_fill_backpressure_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task hold_single_fill();
    extern task add_candidate_while_stalled();
endclass

task mshr_fill_backpressure_sequence::body();
    required_rounds = 2;
    hold_single_fill();
    add_candidate_while_stalled();
    required_hits["fill_stall"] = 16;
    required_hits["fill_new_candidate"] = 1;
    required_hits["fill_stall_release"] = 2;
endtask

// 单个fill反压八拍，replay接收保持开启，以暴露提前重放或释放。
task mshr_fill_backpressure_sequence::hold_single_fill();
    mshr_expected_line group[$];

    cfg.fill_enable = 0;
    prepare_group(1, 1, group);
    obs.wait_count("fill_stall", 8);
    query_line(group[0], group[0]);
    finish_round();
endtask

// 先返回较高Entry使其fill挂起，再返回较低Entry；不要求低位优先，只要求旧请求不可抢占。
task mshr_fill_backpressure_sequence::add_candidate_while_stalled();
    mshr_expected_line group[$];
    int stall_start;

    // 两条Entry使用不同地址和数据，暂停响应，避免场景准备时已完成fill。
    cfg.mem_response_enable = 0;
    cfg.fill_enable = 0;
    prepare_group(2, 2, group);
    obs.wait_count("send", expected_alloc);
    stall_start = obs.hits["fill_stall"];
    respond_entry(group[1].entry);
    obs.wait_count("fill_stall", stall_start + 4);

    // 旧fill仍受阻时让另一Entry获得完整行；保持四拍后才放行。
    respond_entry(group[0].entry);
    obs.wait_cycles(4);
    query_matrix(group[0], group[1]);
    finish_round();
endtask
