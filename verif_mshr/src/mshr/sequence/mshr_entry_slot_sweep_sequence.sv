// 同时占用所有Entry，逐位置覆盖纯读/纯写、首末word、所有set及CPU ID轮换。
class mshr_entry_slot_sweep_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_entry_slot_sweep_sequence)

    function new(string name = "mshr_entry_slot_sweep_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 同时占用所有Entry，逐位置覆盖纯读/纯写、首末word、所有set及CPU ID轮换。
task mshr_entry_slot_sweep_sequence::body();
    mshr_expected_line group[$];

    check_all_positions = 1;
    required_rounds = NUM_SETS * 2;
    for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
        for (int write_kind = 0; write_kind < 2; write_kind++) begin
            cfg.mem_response_enable = 0;
            group.delete();
            for (int entry_index = 0; entry_index < MSHR_ENTRIES; entry_index++) begin
                mshr_expected_line line;
                line = prepare_line(set_index + entry_index * NUM_SETS, entry_index % NUM_WAYS);
                // 同set使用tag的0、1、最大值减1、最大值，覆盖地址字段高低边界。
                case (entry_index)
                    0: line.addr = ADDR_WIDTH'(set_index * BLOCK_SIZE);
                    1: line.addr = block_address(set_index);
                    2: line.addr = (ADDR_WIDTH'({TAG_WIDTH{1'b1}} - 1) << (INDEX_WIDTH + $clog2(BLOCK_SIZE))) |
                        ADDR_WIDTH'(set_index * BLOCK_SIZE);
                    default: line.addr = (ADDR_WIDTH'({TAG_WIDTH{1'b1}}) << (INDEX_WIDTH + $clog2(BLOCK_SIZE))) |
                        ADDR_WIDTH'(set_index * BLOCK_SIZE);
                endcase
                // memory是C++ SparseMemory的SV封装；这里只预置边界地址的数据。
                memory.write_line(line.addr, line.initial_data);
                group.push_back(line);
                for (int slot_index = 0; slot_index < MSHR_MAX_PENDING; slot_index++) begin
                    request_slot(line, bit'(write_kind), (slot_index + set_index) % 2 == 0 ? 0 : WORDS_PER_BLOCK - 1,
                        DATA_WIDTH'('hab000000 + set_index * 256 + entry_index * 16 + slot_index));
                end
            end
            finish_round();
        end
    end
endtask
