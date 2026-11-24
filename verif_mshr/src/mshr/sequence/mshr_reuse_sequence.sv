// 各Entry经历多Slot含写、单Slot纯读、新数据多Slot三轮，验证同址复用没有旧数据和状态污染。
class mshr_reuse_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_reuse_sequence)

    function new(string name = "mshr_reuse_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 各Entry经历多Slot含写、单Slot纯读、新数据多Slot三轮，验证同址复用没有旧数据和状态污染。
task mshr_reuse_sequence::body();
    mshr_expected_line group[$];

    required_rounds = 3;
    for (int round_index = 0; round_index < 3; round_index++) begin
        cfg.mem_response_enable = 0;
        prepare_group(MSHR_ENTRIES, round_index == 1 ? 1 : MSHR_MAX_PENDING, group);
        finish_round();
    end
endtask
