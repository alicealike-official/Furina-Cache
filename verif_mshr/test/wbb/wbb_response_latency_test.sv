class wbb_response_latency_test extends wbb_base_test;
    `uvm_component_utils(wbb_response_latency_test)

    function new(string name = "wbb_response_latency_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
endclass

function void wbb_response_latency_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 1;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
endfunction

// 实际DUT逐笔发送再响应；同时比较ID和采样沿，不能只检查配置值已设置。
task wbb_response_latency_test::run_sequence();
    wbb_response_latency_sequence seq;
    seq = wbb_response_latency_sequence::type_id::create("seq");
    run_scenario(seq, 4);

    // 每笔在下一笔开始前排空，因此两个历史队列的位置和生命周期一一对应。
    check_count("latency send records", env.activity.send_cycles.size(), 4);
    check_count("latency response records", env.activity.response_cycles.size(), 4);
    if (env.activity.send_cycles.size() != 4 || env.activity.response_cycles.size() != 4) begin
        return;
    end
    for (int delay_index = 0; delay_index < 4; delay_index++) begin
        check_count("response matches sent ID", env.activity.response_ids[delay_index],
            env.activity.send_ids[delay_index]);
        check_count("exact response latency", int'(env.activity.response_cycles[delay_index] -
            env.activity.send_cycles[delay_index]), seq.latencies[delay_index]);
        `info($sformatf("id=%0d latency_cycles=%0d observed_cycles=%0d",
            env.activity.send_ids[delay_index], seq.latencies[delay_index],
            env.activity.response_cycles[delay_index] - env.activity.send_cycles[delay_index]), "WBB_LATENCY_COVERAGE")
    end
endtask
