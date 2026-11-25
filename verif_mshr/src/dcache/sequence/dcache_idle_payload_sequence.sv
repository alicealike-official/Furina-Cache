// idle_payload场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_idle_payload_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_idle_payload_sequence)
    function new(string name = "dcache_idle_payload_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_idle_payload_sequence::body();
    dcache_transaction item;
    for (int phase_index = 0; phase_index < 2; phase_index++) begin
        cfg.read_response_enable = 0;
        if (phase_index == 1) access(address(0, 1), 0, 0, 0);
        for (int index = 0; index < 16; index++) begin
            item = dcache_transaction::type_id::create("idle");
            start_item(item);
            // 【防御性检查】无效载荷也按合法位宽随机，valid始终为0。
            if (!item.randomize()) `fatal("Idle randomization failed", "DCACHE_RANDOMIZE")
            item.idle_payload = 1;
            cfg.idle_response_id = 4'(index);
            cfg.idle_response_data = pattern_line(8, index);
            finish_item(item);
        end
    end
    finish_scenario();
    record_check("only one real CPU transaction", obs.requests, 1);
    record_check("only one memory read", obs.reads, 1);
endtask
