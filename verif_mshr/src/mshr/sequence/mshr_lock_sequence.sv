// 同set占满所有way并经历等待、填充、重放，再检查不同set的独立锁矩阵。
class mshr_lock_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_lock_sequence)

    function new(string name = "mshr_lock_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 同set占满所有way并经历等待、填充、重放，再检查不同set的独立锁矩阵。
task mshr_lock_sequence::body();
    mshr_expected_line group[$];

    required_rounds = 2;
    cfg.mem_response_enable = 0;
    cfg.replay_enable = 0;
    prepare_group(MSHR_ENTRIES, 2, group, NUM_SETS - 1, 1);
    obs.wait_cycles(4);
    cfg.mem_response_enable = 1;
    obs.wait_count("fill", MSHR_ENTRIES);
    obs.wait_cycles(4);
    finish_round();
    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 1, group);
    finish_round();
    required_hits["all_ways_locked"] = 8;
endtask
