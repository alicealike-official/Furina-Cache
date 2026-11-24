// 遍历RR/RW/WR/WW和四Slot历史序列，覆盖同字/异字、首末字及两种可合并阶段。
class mshr_merge_matrix_sequence extends mshr_scenario_sequence;
    bit history_only = 0;
    `uvm_object_utils(mshr_merge_matrix_sequence)

    function new(string name = "mshr_merge_matrix_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 遍历RR/RW/WR/WW和四Slot历史序列，覆盖同字/异字、首末字及两种可合并阶段。
task mshr_merge_matrix_sequence::body();
    mshr_expected_line line;
    int sequence_bits;
    int slot_total;
    int word_index;

    required_rounds = 0;
    for (int phase_index = 0; phase_index < 2; phase_index++) begin
        for (int relation = 0; relation < 2; relation++) begin
            for (int edge_word = 0; edge_word < 2; edge_word++) begin
                for (int combination = 0; combination < 4; combination++) begin
                    cfg.mem_request_enable = phase_index != 0;
                    cfg.mem_response_enable = 0;
                    line = prepare_line(0, 0, 4, completed_rounds);
                    slot_total = history_only ? 4 : 2;
                    case (combination)
                        0: sequence_bits = history_only ? 4'b1010 : 0;
                        1: sequence_bits = history_only ? 4'b0101 : 1;
                        2: sequence_bits = history_only ? 4'b0110 : 2;
                        default: sequence_bits = history_only ? 4'b1001 : 3;
                    endcase
                    for (int slot_index = 0; slot_index < slot_total; slot_index++) begin
                        word_index = edge_word == 0 ? 0 : WORDS_PER_BLOCK - 1;
                        if (relation != 0 && slot_index % 2 != 0) word_index = WORDS_PER_BLOCK - 1 - word_index;
                        request_slot(line, bit'((sequence_bits >> slot_index) & 1), word_index,
                            DATA_WIDTH'('hce000000 + completed_rounds * 16 + slot_index));
                    end
                    finish_round();
                    required_rounds++;
                end
            end
        end
    end
endtask
