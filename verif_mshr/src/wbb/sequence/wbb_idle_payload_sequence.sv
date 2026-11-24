class wbb_idle_payload_sequence extends wbb_scenario_sequence;
    `uvm_object_utils(wbb_idle_payload_sequence)

    function new(string name = "wbb_idle_payload_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task disturb_payloads();
endclass

task wbb_idle_payload_sequence::body();
    // 空态先扰动，再存入一笔真实写回并保持pending，重复同样扰动。
    obs.wait_cycles(1);
    cfg.mem_send_enable = 0;
    cfg.mem_response_enable = 0;
    disturb_payloads();
    send_line(0);
    disturb_payloads();

    // 放行原有写回，检查扰动没有破坏其保存的数据或生成额外事务。
    cfg.idle_response_id = 0;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 1;
    obs.wait_until_empty();
endtask

// 通过各自driver驱动无效字段；sequence只提供数据与配置，不直接驱动接口。
task wbb_idle_payload_sequence::disturb_payloads();
    for (int variant = 0; variant < 8; variant++) begin
        wbb_transaction item;
        obs.wait_cycles(1);
        cfg.idle_response_id = BUS_ID_WIDTH'(variant + 1);
        item = wbb_transaction::type_id::create("inactive_payload");
        item.operation = WBB_QUERY;
        item.idle_payload_enable = 1;
        item.addr = block_addr(100 + variant);
        item.line_data = make_line(100 + variant);
        item.idle_push_slot = SLOT_WIDTH'(variant);
        item.q0Addr = block_addr(0);
        item.q1Addr = block_addr(100 + variant);
        item.cycles = 2;
        step(item);
    end
endtask
