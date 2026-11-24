// 空态及已占用状态下扰动alloc/merge/响应的无效载荷，最后完成唯一合法请求。
class mshr_idle_payload_sequence extends mshr_scenario_sequence;
    `uvm_object_utils(mshr_idle_payload_sequence)

    function new(string name = "mshr_idle_payload_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

// 空态及已占用状态下扰动alloc/merge/响应的无效载荷，最后完成唯一合法请求。
task mshr_idle_payload_sequence::body();
    mshr_expected_line line;
    mshr_transaction item;

    cfg.mem_response_enable = 0;
    for (int phase_index = 0; phase_index < 2; phase_index++) begin
        if (phase_index == 1) begin
            line = prepare_line(0, 0);
            request_slot(line, 0, 0, 0);
        end
        for (int iteration = 0; iteration < 16; iteration++) begin
            item = mshr_transaction::type_id::create("invalid_payload");
            // 【防御性检查】只随机合法位宽字段，操作使能始终保持0。
            if (!item.randomize()) `fatal("Idle payload randomization failed", "MSHR_RANDOMIZE")
            item.operation = MSHR_QUERY;
            item.idle_payload_enable = 1;
            item.entry = ENTRY_WIDTH'(iteration % MSHR_ENTRIES);
            cfg.idle_response_id = BUS_ID_WIDTH'(iteration);
            cfg.idle_response_data = make_data(8, iteration);
            step(item);
        end
    end
    finish_round();
endtask
