class wbb_reuse_test extends wbb_base_test;
    `uvm_component_utils(wbb_reuse_test)

    function new(string name = "wbb_reuse_test", uvm_component parent = null);
        super.new(name, parent);
        supports_input_modes = 1;
    endfunction

    extern virtual task run_sequence();
endclass

// 三轮都用满全部槽，检查每槽至少使用3次，并保留原模型对每次send版本的逐拍检查。
task wbb_reuse_test::run_sequence();
    wbb_reuse_sequence seq;

    seq = wbb_reuse_sequence::type_id::create("seq");
    run_scenario(seq, 3 * WBB_ENTRIES);
    for (int slot = 0; slot < WBB_ENTRIES; slot++) begin
        check_count($sformatf("slot %0d reuse", slot), env.activity.reserve_uses[slot], 3);
    end
    for (int round_index = 0; round_index < 3; round_index++) begin
        check_count($sformatf("reuse round %0d overlap", round_index), seq.round_overlaps[round_index],
            cfg.input_mode == WBB_INPUT_PIPELINE ? WBB_ENTRIES - 1 : 0);
    end
    check_count("old address misses while new address is issued", env.activity.query_matrix[0][3], 3 * WBB_ENTRIES, 1);
    check_count("empty queries after responses", env.activity.empty_query_cycles, 3 * WBB_ENTRIES, 1);
    `info($sformatf("rounds=3 writebacks=%0d old_miss_new_hit=%0d empty_queries=%0d overlaps=%0d/%0d/%0d",
        3 * WBB_ENTRIES, env.activity.query_matrix[0][3], env.activity.empty_query_cycles,
        seq.round_overlaps[0], seq.round_overlaps[1], seq.round_overlaps[2]), "WBB_REUSE_COVERAGE")
endtask
