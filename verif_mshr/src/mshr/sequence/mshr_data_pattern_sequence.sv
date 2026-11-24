// 遍历九种整行数据，单1/单0覆盖全部512位；纯读遍历字位置，另混合写检查未写字保持。
class mshr_data_pattern_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_data_pattern_sequence)

    function new(string name = "mshr_data_pattern_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 遍历九种整行数据，单1/单0覆盖全部512位；纯读遍历字位置，另混合写检查未写字保持。
task mshr_data_pattern_sequence::body();
    mshr_expected_line line;
    int iterations;

    required_rounds = 0;
    check_patterns = 1;
    for (int pattern = 0; pattern < 9; pattern++) begin
        iterations = pattern inside {6, 7} ? LINE_WIDTH : WORDS_PER_BLOCK;
        for (int position = 0; position < iterations; position++) begin
            cfg.mem_response_enable = 0;
            line = prepare_line(0, position % NUM_WAYS, pattern, position);
            // 纯读先验证原始行全部位，不能让后续写覆盖掩盖walking位。
            request_slot(line, 0, pattern inside {6, 7} ? position / DATA_WIDTH : position % WORDS_PER_BLOCK, 0);
            finish_round();
            required_rounds++;

            // 再以相同原始行验证单字覆盖及后续读历史。
            cfg.mem_response_enable = 0;
            line = prepare_line(0, position % NUM_WAYS, pattern, position);
            request_slot(line, 0, position % WORDS_PER_BLOCK, 0);
            request_slot(line, 1, (position + 1) % WORDS_PER_BLOCK, DATA_WIDTH'(~position));
            request_slot(line, 0, (position + 1) % WORDS_PER_BLOCK, 0);
            finish_round();
            pattern_counts[pattern]++;
            required_rounds++;
        end
    end
endtask
