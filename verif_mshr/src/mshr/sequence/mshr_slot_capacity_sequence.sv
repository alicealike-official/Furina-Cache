// 分别在SEND和MISS_WAIT填满每个Entry的Slot，满后只查询，不提交非法merge。
class mshr_slot_capacity_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_slot_capacity_sequence)

    function new(string name = "mshr_slot_capacity_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 分别在SEND和MISS_WAIT填满每个Entry的Slot，满后只查询，不提交非法merge。
task mshr_slot_capacity_sequence::body();
    mshr_expected_line group[$];

    required_rounds = 2;
    for (int phase_index = 0; phase_index < 2; phase_index++) begin
        cfg.mem_response_enable = 0;
        cfg.mem_request_enable = phase_index != 0;
        prepare_group(MSHR_ENTRIES, MSHR_MAX_PENDING, group);
        foreach (group[index]) query_line(group[index], group[index]);
        obs.wait_cycles(4);
        finish_round();
    end
    required_hits["entry_full"] = 4;
    required_hits["boundary_last_slot_stage_1"] = MSHR_ENTRIES;
    required_hits["boundary_last_slot_stage_2"] = MSHR_ENTRIES;
    required_hits["slot_full"] = MSHR_ENTRIES * 2;
endtask
