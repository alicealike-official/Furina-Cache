// 由公开请求/响应及阻塞恢复证明容量边界，不读取内部占用计数。
class dcache_wbb_capacity_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_wbb_capacity_sequence)
    function new(string name = "dcache_wbb_capacity_sequence");
        super.new(name);
    endfunction
    task body();
    dirty_set(0);
    cfg.write_response_enable = 0;
    evict_set(0);
    obs.wait_cycles(16);
    record_check("four writebacks await acknowledgement", obs.writes-obs.write_acks, 4);
    fork
        access(address(1, 1), 0, 0, 0);
        begin
            obs.wait_cycles(32);
            record_check("no fifth unacknowledged write", obs.writes-obs.write_acks, 4);
            cfg.write_response_enable = 1;
        end
    join
    finish_scenario();
    check_evicted_set(0);
    required_hits["cpu_stall"] = 1;
    endtask
endclass
