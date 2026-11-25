// 由公开请求/响应及阻塞恢复证明容量边界，不读取内部占用计数。
class dcache_entry_capacity_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_entry_capacity_sequence)
    function new(string name = "dcache_entry_capacity_sequence");
        super.new(name);
    endfunction
    task body();
    cfg.read_response_enable = 0;
    for (int index = 0; index < 4; index++) access(address(index, 1), 0, 0, 0);
    obs.wait_cycles(16);
    record_check("four distinct memory reads outstanding", obs.reads-obs.read_acks, 4);
    access(address(0, 1, 1), 0, 0, 0);
    record_check("same-line CPU request accepted while four reads pending", obs.requests, 5);
    fork
        access(address(4, 1), 0, 0, 0);
        begin
            obs.wait_cycles(32);
            record_check("fifth memory read waits for capacity", obs.reads, 4);
            cfg.read_response_enable = 1;
        end
    join
    finish_scenario();
    record_check("five blocks fetched after release", obs.reads, 5);
    required_hits["cpu_stall"] = 1;
    endtask
endclass
