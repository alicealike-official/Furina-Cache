// 由公开请求/响应及阻塞恢复证明容量边界，不读取内部占用计数。
class dcache_slot_capacity_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_slot_capacity_sequence)
    function new(string name = "dcache_slot_capacity_sequence");
        super.new(name);
    endfunction
    task body();
    for (int phase_index = 0; phase_index < 2; phase_index++) begin
        int before_reads;
        before_reads = obs.reads;
        cfg.read_request_enable = phase_index != 0;
        cfg.read_response_enable = 0;
        for (int index = 0; index < 4; index++) access(address(phase_index, 1, index), index % 2, 'h76120000+index, 0);
        fork
            begin
                access(address(phase_index, 1, 4), 0, 0, 0);
                access(address(phase_index, 1, 5), 0, 0, 0);
            end
            begin
                obs.wait_cycles(32);
                cfg.read_request_enable = 1;
                cfg.read_response_enable = 1;
            end
        join
        obs.wait_empty();
        record_check("all same-line requests use one fetch", obs.reads-before_reads, 1);
    end
    finish_scenario();
    required_hits["cpu_stall"] = 1;
    endtask
endclass
