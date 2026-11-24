// 全Entry占用时仍向旧Entry合法merge；完成其中一条后分配新块，确认容量恢复。
class mshr_entry_capacity_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_entry_capacity_sequence)

    function new(string name = "mshr_entry_capacity_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 全Entry占用时仍向旧Entry合法merge；完成其中一条后分配新块，确认容量恢复。
task mshr_entry_capacity_sequence::body();
    mshr_expected_line group[$];
    mshr_expected_line replacement;

    cfg.mem_response_enable = 0;
    prepare_group(MSHR_ENTRIES, 1, group);
    obs.wait_cycles(4);
    request_slot(group[0], 1, WORDS_PER_BLOCK - 1, 'hdeadbeef);
    obs.wait_count("send", MSHR_ENTRIES);
    respond_entry(group[0].entry);
    obs.wait_count("release", 1);
    replacement = prepare_line(NUM_SETS - 1, NUM_WAYS - 1);
    request_slot(replacement, 0, WORDS_PER_BLOCK - 1, 0);
    finish_round();
    required_hits["entry_full"] = 4;
    required_hits["boundary_full_merge"] = 1;
    required_hits["boundary_full_release"] = 1;
    required_hits["boundary_full_release_recovery"] = 1;
endtask
