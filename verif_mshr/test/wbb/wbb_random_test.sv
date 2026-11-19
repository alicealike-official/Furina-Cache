// 通过多批合法随机写回检查数据、查询、ready变化、响应乱序及地址复用后的完整结束。
class wbb_random_test extends wbb_base_test;
    `uvm_component_utils(wbb_random_test)

    function new(string name = "wbb_random_test",
        uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
endclass

function void wbb_random_test::build_phase(uvm_phase phase);
    int minimum_timeout;

    super.build_phase(phase);
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_send_enable = 0;
    cfg.mem_response_enable = 0;
    cfg.mem_random_ready = 1;
    cfg.mem_ready_percent = 60;
    cfg.mem_random_latency = 1;
    cfg.mem_min_latency_cycles = 1;
    cfg.mem_max_latency_cycles = 8;
    cfg.mem_response_order = WBB_MEM_RANDOM;
    minimum_timeout = wbb_random_sequence::BATCH_COUNT * (16 * WBB_ENTRIES + 32) + 200;
    if (cfg.timeout_cycles < minimum_timeout) begin
        cfg.timeout_cycles = minimum_timeout;
    end
endfunction

// 运行多批随机激励，检查写回总数、完成批数，以及背压和乱序确实发生；随机数据由sequence生成。
task wbb_random_test::run_sequence();
    wbb_random_sequence seq;
    string seed_text;

    seed_text = "simulator-default";
    void'($value$plusargs("ntb_random_seed=%s", seed_text));
    `info($sformatf("seed=%s batches=%0d writebacks=%0d ready_percent=%0d latency_range=%0d..%0d cycles",
        seed_text, wbb_random_sequence::BATCH_COUNT, wbb_random_sequence::WRITEBACK_COUNT,
        cfg.mem_ready_percent, cfg.mem_min_latency_cycles, cfg.mem_max_latency_cycles), "WBB_RANDOM_CONFIG")
    seq = wbb_random_sequence::type_id::create("seq");
    run_scenario(seq, wbb_random_sequence::WRITEBACK_COUNT);
    check_count("completed random batches", seq.completed_batches, wbb_random_sequence::BATCH_COUNT);
    check_count("randomized complete lines", seq.randomized_lines, wbb_random_sequence::WRITEBACK_COUNT);
    check_count("random case send stalls", env.activity.send_stall_cycles, 3, 1);
    check_count("random case reordered responses", env.activity.response_reorders, 1, 1);
    check_count("random case final occupied slots", $countones(env.activity.occupied), 0);
    `info($sformatf("batches=%0d lines=%0d stalled_cycles=%0d reordered_responses=%0d",
        seq.completed_batches, seq.randomized_lines, env.activity.send_stall_cycles,
        env.activity.response_reorders), "WBB_RANDOM_COVERAGE")
endtask
