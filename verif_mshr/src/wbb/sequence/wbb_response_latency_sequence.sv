class wbb_response_latency_sequence extends wbb_scenario_sequence;
    int latencies[4] = '{1, 2, 7, 32};
    `uvm_object_utils(wbb_response_latency_sequence)

    function new(string name = "wbb_response_latency_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

task wbb_response_latency_sequence::body();
    // 每笔独立排空，排除队首等待，把实际握手间隔与配置拍数直接对应。
    for (int delay_index = 0; delay_index < 4; delay_index++) begin
        obs.wait_cycles(1);
        cfg.mem_write_latency_cycles = latencies[delay_index];
        send_line(delay_index);
        obs.wait_until_empty();
    end
endtask
