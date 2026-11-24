// 所有请求已发后逆序返回实际Entry ID，再进行一轮连续拍FIFO响应。
class mshr_response_order_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_response_order_sequence)

    function new(string name = "mshr_response_order_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 所有请求已发后逆序返回实际Entry ID，再进行一轮连续拍FIFO响应。
task mshr_response_order_sequence::body();
    mshr_expected_line group[$];

    required_rounds = 3;
    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group);
    obs.wait_count("send", MSHR_ENTRIES);
    for (int index = MSHR_ENTRIES - 1; index >= 0; index--) respond_entry(obs.send_ids[index]);
    finish_round();
    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group);
    obs.wait_count("send", 2 * MSHR_ENTRIES);
    finish_round();
    // 指定一个既非FIFO也非逆序的排列，按实际Entry身份响应。
    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group);
    obs.wait_count("send", expected_alloc);
    respond_entry(group[1].entry);
    respond_entry(group[3].entry);
    respond_entry(group[0].entry);
    respond_entry(group[2].entry);
    finish_round();
    required_hits["reorder"] = MSHR_ENTRIES - 1;
    required_hits["adjacent_responses"] = MSHR_ENTRIES - 1;
endtask
