// 将两条Entry依次停在SEND、MISS_WAIT、待fill和待replay，重复扫描双查询组合。
class mshr_query_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_query_sequence)

    function new(string name = "mshr_query_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 将两条Entry依次停在SEND、MISS_WAIT、待fill和待replay，重复扫描双查询组合。
task mshr_query_sequence::body();
    mshr_expected_line group[$];

    cfg.mem_request_enable = 0;
    cfg.mem_response_enable = 0;
    cfg.fill_enable = 0;
    cfg.replay_enable = 0;
    prepare_group(2, 1, group);
    query_matrix(group[0], group[1]);
    cfg.mem_request_enable = 1;
    obs.wait_count("send", 2);
    query_matrix(group[0], group[1]);
    cfg.mem_response_enable = 1;
    obs.wait_count("response", 2);
    query_matrix(group[0], group[1]);
    cfg.fill_enable = 1;
    obs.wait_count("fill", 2);
    query_matrix(group[0], group[1]);
    finish_round();
    query_matrix(group[0], group[1]);
    required_hits["query_0_0"] = 1;
    required_hits["query_1_0"] = 1;
    required_hits["query_0_1"] = 1;
    required_hits["query_1_1"] = 1;
    required_hits["query_different"] = 1;
    required_hits["query_stage_1"] = 1;
    required_hits["query_stage_2"] = 1;
    required_hits["query_stage_3"] = 1;
endtask
