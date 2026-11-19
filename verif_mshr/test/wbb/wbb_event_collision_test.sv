// 检查不同槽的response分别与reserve、push和send同拍，三个目标事件都必须实际出现。
class wbb_event_collision_test extends wbb_base_test;
    `uvm_component_utils(wbb_event_collision_test)

    function new(string name = "wbb_event_collision_test",
        uvm_component parent = null);
        super.new(name, parent);
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

// 运行三组独立交叉场景，数据、槽归属及沿前资源规则继续由已有模型和SVA逐拍检查。
task wbb_event_collision_test::run_sequence();
    wbb_event_collision_sequence seq;

    seq = wbb_event_collision_sequence::type_id::create("seq");
    run_scenario(seq, wbb_event_collision_sequence::WRITEBACK_COUNT);
    check_count("reserve with different-slot response", env.activity.reserve_response_cycles, 1, 1);
    check_count("push with different-slot response", env.activity.push_response_cycles, 1, 1);
    check_count("send with different-slot response", env.activity.send_response_cycles, 1, 1);
    `info($sformatf("reserve_response=%0d push_response=%0d send_response=%0d",
        env.activity.reserve_response_cycles, env.activity.push_response_cycles,
        env.activity.send_response_cycles), "WBB_COLLISION_COVERAGE")
endtask
