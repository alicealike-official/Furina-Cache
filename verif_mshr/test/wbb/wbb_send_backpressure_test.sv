// 检查send被背压时加入新候选，原请求的valid、地址、数据和ID仍保持到握手。
class wbb_send_backpressure_test extends wbb_base_test;
    `uvm_component_utils(wbb_send_backpressure_test)

    function new(string name = "wbb_send_backpressure_test",
        uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
endclass

function void wbb_send_backpressure_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 2;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
endfunction

// 运行背压插入场景，并确认插入前后都存在停顿，且期间确实push了另一槽的新候选。
// 原请求是否保持正确由公共scoreboard和IO SVA检查，不能因为最终数据正确而忽略中途变化。
task wbb_send_backpressure_test::run_sequence();
    wbb_send_backpressure_sequence seq;

    seq = wbb_send_backpressure_sequence::type_id::create("seq");
    run_scenario(seq, wbb_send_backpressure_sequence::WRITEBACK_COUNT);
    check_count("send stalled before insertion", int'(seq.stalled_before_insert), 1);
    check_count("send still stalled after insertion", int'(seq.stalled_after_insert), 1);
    check_count("lower-index competing slot", int'(seq.competing_id < seq.stalled_id), 1);
    check_count("send backpressure cycles", env.activity.send_stall_cycles, 4, 1);
    check_count("new candidate pushed during stall", env.activity.stall_new_candidate_cycles, 1, 1);
    `info($sformatf("held_id=%0d competing_id=%0d stalled_cycles=%0d candidate_insertions=%0d",
        seq.stalled_id, seq.competing_id, env.activity.send_stall_cycles,
        env.activity.stall_new_candidate_cycles), "WBB_BACKPRESSURE_COVERAGE")
endtask
