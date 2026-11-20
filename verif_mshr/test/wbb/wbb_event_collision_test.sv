// 串行检查三类两事件交叉；流水检查不同槽的reserve/push/response及四事件同拍。
class wbb_event_collision_test extends wbb_base_test;
    `uvm_component_utils(wbb_event_collision_test)

    function new(string name = "wbb_event_collision_test",
        uvm_component parent = null);
        super.new(name, parent);
        supports_input_modes = 1;
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
endclass

function void wbb_event_collision_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 1;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
endfunction

// 按输入模式选择交叉场景，数据、槽归属及沿前资源规则继续由已有模型和SVA逐拍检查。
task wbb_event_collision_test::run_sequence();
    wbb_event_collision_sequence seq;
    int expected_writebacks;

    seq = wbb_event_collision_sequence::type_id::create("seq");
    expected_writebacks = cfg.input_mode == WBB_INPUT_PIPELINE ?
        wbb_event_collision_sequence::PIPELINE_WRITEBACK_COUNT : wbb_event_collision_sequence::WRITEBACK_COUNT;
    run_scenario(seq, expected_writebacks);
    check_count("reserve with different-slot response", env.activity.reserve_response_cycles, 1, 1);
    check_count("push with different-slot response", env.activity.push_response_cycles, 1, 1);
    check_count("send with different-slot response", env.activity.send_response_cycles, 1, 1);
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        check_count("pipeline reserve/push/response", env.activity.reserve_push_response_cycles, 2);
        check_count("pipeline reserve/push/send/response", env.activity.reserve_push_send_response_cycles, 1);
    end
    `info($sformatf("reserve_response=%0d push_response=%0d send_response=%0d triple_events=%0d four_events=%0d",
        env.activity.reserve_response_cycles, env.activity.push_response_cycles,
        env.activity.send_response_cycles, env.activity.reserve_push_response_cycles,
        env.activity.reserve_push_send_response_cycles), "WBB_COLLISION_COVERAGE")
endtask
