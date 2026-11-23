// 仅在显式延迟push编译模式运行，检查等待push期间的占用、查询和禁止提前发送。
class wbb_delayed_push_test extends wbb_base_test;
    `uvm_component_utils(wbb_delayed_push_test)

    function new(string name = "wbb_delayed_push_test",
        uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
endclass

function void wbb_delayed_push_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】核对编译模式是否支持本操作，避免环境模式与协议检查配置不一致。
`ifndef WBB_ALLOW_DELAYED_PUSH
    `fatal("Compile wbb_delayed_push_test with WBB_ALLOW_DELAYED_PUSH", "WBB_DELAYED_MODE")
`endif
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 2;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 1;
endfunction

// 确认单笔及整批都发生了延迟push，并且实际保持过所有槽已预留但都未push的满状态。
task wbb_delayed_push_test::run_sequence();
    wbb_delayed_push_sequence seq;

    seq = wbb_delayed_push_sequence::type_id::create("seq");
    run_scenario(seq, wbb_delayed_push_sequence::WRITEBACK_COUNT);
    check_count("delayed push transactions", env.activity.delayed_push_count,
        wbb_delayed_push_sequence::WRITEBACK_COUNT, 1);
    check_count("maximum reserve-to-push delay", env.activity.max_push_delay,
        wbb_delayed_push_sequence::SINGLE_PUSH_DELAY, 1);
    check_count("all slots reserved before any push", env.activity.full_reserved_cycles,
        wbb_delayed_push_sequence::BATCH_HOLD_CYCLES, 1);
    check_count("both queries match reserved slots", env.activity.query_matrix[1][1], 1, 1);
    check_count("batch pending slots", env.activity.max_pending, WBB_ENTRIES, 1);
    `info($sformatf("delayed_pushes=%0d maximum_delay=%0d all_reserved_cycles=%0d",
        env.activity.delayed_push_count, env.activity.max_push_delay,
        env.activity.full_reserved_cycles), "WBB_DELAYED_PUSH_COVERAGE")
endtask
