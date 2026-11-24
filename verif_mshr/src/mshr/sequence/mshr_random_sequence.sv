// 每轮并存4个Entry，各自随机1到4个Slot；随机接收、延迟及乱序响应后排空并复用地址。
class mshr_random_sequence extends mshr_scenario_sequence;
    int rounds = 128;
    bit force_full_slots = 0;
    `uvm_object_utils(mshr_random_sequence)

    function new(string name = "mshr_random_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 每轮并存4个Entry，各自随机1到4个Slot；随机接收、延迟及乱序响应后排空并复用地址。
task mshr_random_sequence::body();
    mshr_expected_line line;
    int slot_total;
    int word_index;
    bit is_write;
    bit [DATA_WIDTH-1:0] data;

    required_rounds = rounds;
    cfg.random_request_ready = 1;
    cfg.random_latency = 1;
    cfg.max_latency_cycles = 32;
    cfg.random_sinks = 1;
    for (int round_index = 0; round_index < rounds; round_index++) begin
        cfg.mem_response_enable = 0;
        cfg.mem_order = MSHR_MEM_RANDOM;
        for (int entry_index = 0; entry_index < MSHR_ENTRIES; entry_index++) begin
            line = prepare_line(entry_index, entry_index % NUM_WAYS);
            slot_total = force_full_slots ? MSHR_MAX_PENDING : $urandom_range(MSHR_MAX_PENDING, 1);
            for (int slot_index = 0; slot_index < slot_total; slot_index++) begin
                // 【防御性检查】随机化必须生成合法字偏移，失败不能提交默认请求。
                if (!std::randomize(word_index, is_write, data) with {
                    word_index inside {[0:WORDS_PER_BLOCK-1]};
                }) begin
                    `fatal("Random Slot generation failed", "MSHR_RANDOMIZE")
                end
                request_slot(line, is_write, word_index, data);
            end
        end
        obs.wait_count("send", expected_alloc);
        cfg.mem_response_enable = 1;
        obs.wait_empty();
        obs.wait_cycles(2);
        completed_rounds++;
    end
    cfg.random_request_ready = 0;
    cfg.random_latency = 0;
    cfg.random_sinks = 0;
    required_hits["reorder"] = 1;
    required_hits["entry_full"] = rounds;
endtask
