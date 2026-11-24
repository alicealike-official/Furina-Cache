// 长时间写回、槽位复用和三轮同址更新；使用已有模型、SVA及base中的数据/计数检查。
class wbb_long_run_test extends wbb_base_test;
    `uvm_component_utils(wbb_long_run_test)

    function new(string name = "wbb_long_run_test", uvm_component parent = null);
        super.new(name, parent);
        supports_input_modes = 1;
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern task run_round(int round_index);
endclass

function void wbb_long_run_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_random_ready = 1;
    cfg.mem_ready_percent = 60;
    cfg.mem_random_latency = 1;
    cfg.mem_min_latency_cycles = 1;
    cfg.mem_max_latency_cycles = 32;
    cfg.mem_response_order = WBB_MEM_RANDOM;
    // 总超时以拍计，覆盖随机背压、最长响应延迟和每轮收尾。
    if (cfg.timeout_cycles < wbb_long_run_sequence::WRITEBACK_COUNT * 128) begin
        cfg.timeout_cycles = wbb_long_run_sequence::WRITEBACK_COUNT * 128;
    end
endfunction

// 逐轮检查4096笔完整写回，再检查全程总数；每轮回读内存，避免末轮覆盖掩盖旧版本错误。
task wbb_long_run_test::run_sequence();
    string seed_text;

    seed_text = "simulator-default";
    void'($value$plusargs("ntb_random_seed=%s", seed_text));
    `info($sformatf("seed=%s rounds=%0d lines_per_round=%0d writebacks=%0d latency=1..32 cycles ready_percent=60",
        seed_text, wbb_long_run_sequence::ROUND_COUNT, wbb_long_run_sequence::LINES_PER_ROUND,
        wbb_long_run_sequence::WRITEBACK_COUNT), "WBB_LONG_RUN_CONFIG")

    for (int round_index = 0; round_index < wbb_long_run_sequence::ROUND_COUNT; round_index++) begin
        run_round(round_index);
    end
    check_writeback_counts(wbb_long_run_sequence::WRITEBACK_COUNT);
    `info($sformatf("rounds=%0d lines=%0d stalls=%0d reorders=%0d overlaps=%0d final_occupied=%b",
        wbb_long_run_sequence::ROUND_COUNT, wbb_long_run_sequence::WRITEBACK_COUNT,
        env.activity.send_stall_cycles, env.activity.response_reorders,
        env.activity.overlap_count, env.activity.occupied), "WBB_LONG_RUN_COVERAGE")
endtask

// 记录每轮起点，检查各槽确实重复使用、背压/乱序发生，且整轮结束后没有遗留占用。
task wbb_long_run_test::run_round(int round_index);
    wbb_long_run_sequence seq;
    int slot_uses_before[WBB_ENTRIES];
    int stalls_before;
    int reorders_before;
    int full_before;
    int overlaps_before;

    // 保存本轮之前的累计值，避免第一轮的命中代替后续轮次。
    foreach (slot_uses_before[slot]) begin
        slot_uses_before[slot] = env.activity.reserve_uses[slot];
    end
    stalls_before = env.activity.send_stall_cycles;
    reorders_before = env.activity.response_reorders;
    full_before = env.scoreboard.full_cycles;
    overlaps_before = env.activity.overlap_count;

    // run_scenario复用base的四事件计数、原始输入比较与C++ SparseMemory的DPI回读检查。
    seq = wbb_long_run_sequence::type_id::create($sformatf("round_%0d", round_index));
    seq.round_index = round_index;
    run_scenario(seq, wbb_long_run_sequence::LINES_PER_ROUND);

    check_count("long-run randomized lines", seq.randomized_lines, wbb_long_run_sequence::LINES_PER_ROUND);
    check_count("long-run round send stalls", env.activity.send_stall_cycles - stalls_before, 4, 1);
    check_count("long-run round reordered responses", env.activity.response_reorders - reorders_before, 1, 1);
    check_count("long-run round full cycles", env.scoreboard.full_cycles - full_before, 4, 1);
    check_count("long-run round final occupied slots", $countones(env.activity.occupied), 0);
    foreach (slot_uses_before[slot]) begin
        check_count($sformatf("long-run round slot %0d reuse", slot),
            env.activity.reserve_uses[slot] - slot_uses_before[slot], 2, 1);
    end
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        check_count("long-run round overlap", env.activity.overlap_count - overlaps_before, 1, 1);
    end
    `info($sformatf("round=%0d lines=%0d stalls=%0d reorders=%0d full_cycles=%0d overlaps=%0d final_occupied=%b",
        round_index + 1, seq.randomized_lines, env.activity.send_stall_cycles - stalls_before,
        env.activity.response_reorders - reorders_before, env.scoreboard.full_cycles - full_before,
        env.activity.overlap_count - overlaps_before, env.activity.occupied), "WBB_LONG_ROUND_COVERAGE")
endtask
