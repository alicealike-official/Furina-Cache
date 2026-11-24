// 逐笔排空，精确覆盖1/2/7/32拍响应延迟，不把配置值当作实际握手证据。
class mshr_response_latency_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_response_latency_sequence)

    function new(string name = "mshr_response_latency_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 逐笔排空，精确覆盖1/2/7/32拍响应延迟，不把配置值当作实际握手证据。
task mshr_response_latency_sequence::body();
    int delays[4] = '{1, 2, 7, 32};
    mshr_expected_line line;

    required_rounds = 4;
    check_latencies = 1;
    foreach (delays[index]) begin
        cfg.mem_read_latency_cycles = delays[index];
        line = prepare_line(index, index % NUM_WAYS);
        request_slot(line, bit'(index % 2), index, DATA_WIDTH'('hf1234567 + index));
        finish_round();
    end
endtask
