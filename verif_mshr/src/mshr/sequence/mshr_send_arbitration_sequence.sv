// 聚集多发送候选后统一放行，查询与原模型检查仅被握手Entry推进和发送ID/地址。
class mshr_send_arbitration_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_send_arbitration_sequence)

    function new(string name = "mshr_send_arbitration_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 聚集多发送候选后统一放行，查询与原模型检查仅被握手Entry推进和发送ID/地址。
task mshr_send_arbitration_sequence::body();
    mshr_expected_line group[$];
    mshr_expected_line replacement;
    int release_start;

    required_rounds = 2;

    cfg.mem_request_enable = 0;
    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 1, group);
    obs.wait_cycles(4);
    cfg.mem_request_enable = 1;
    obs.wait_count("send", MSHR_ENTRIES);
    finish_round();
    // 第二轮先保留Entry1/3在途，再复用Entry0/2形成非连续SEND候选。
    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 1, group);
    obs.wait_count("send", expected_alloc);
    release_start = obs.hits["release"];
    respond_entry(group[0].entry);
    respond_entry(group[2].entry);
    obs.wait_count("release", release_start + 2);
    cfg.mem_request_enable = 0;
    replacement = prepare_line(8, 0);
    request_slot(replacement, 0, 0, 0);
    replacement = prepare_line(9, 2);
    request_slot(replacement, 0, 0, 0);
    obs.wait_cycles(4);
    finish_round();
    required_hits["send_stall"] = 8;
    required_hits["entry_full"] = 4;
endtask
