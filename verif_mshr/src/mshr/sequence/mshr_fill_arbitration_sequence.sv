// 多Entry均到达待fill后统一放行，检查各目标最终只接受一次，保持由IO SVA检查，不要求特定仲裁顺序。
class mshr_fill_arbitration_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_fill_arbitration_sequence)

    function new(string name = "mshr_fill_arbitration_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 多Entry均到达待fill后统一放行，检查各目标最终只接受一次，保持由IO SVA检查，不要求特定仲裁顺序。
task mshr_fill_arbitration_sequence::body();
    mshr_expected_line group[$];

    cfg.mem_response_enable = 0;
    cfg.fill_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group);
    obs.wait_count("send", MSHR_ENTRIES);
    cfg.mem_order = MSHR_MEM_REVERSE;
    cfg.mem_response_enable = 1;
    obs.wait_count("response", MSHR_ENTRIES);
    obs.wait_cycles(4);
    finish_round();
    required_hits["fill_stall"] = 4;
    required_hits["reorder"] = 1;
endtask
