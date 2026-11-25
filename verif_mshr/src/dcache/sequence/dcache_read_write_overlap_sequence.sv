// read_write_overlap场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_read_write_overlap_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_read_write_overlap_sequence)
    function new(string name = "dcache_read_write_overlap_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_read_write_overlap_sequence::body();
    dirty_set(0);
    cfg.read_request_enable = 0;
    cfg.write_request_enable = 0;
    cfg.read_response_enable = 0;
    cfg.write_response_enable = 0;
    access(address(0, 5), 0, 0, 0);
    obs.wait_cycles(16);
    cfg.read_request_enable = 1;
    cfg.write_request_enable = 1;
    obs.wait_cycles(16);
    record_check("read and write outstanding together", obs.reads > obs.read_acks && obs.writes > obs.write_acks, 1);
    obs.wait_cycles(1);
    cfg.read_response_enable = 1;
    cfg.write_response_enable = 1;
    access(address(1, 1), 0, 0, 0);
    finish_scenario();
    required_hits["dual_responses"] = 1;
    required_hits["dual_requests"] = 1;
    required_hits["cpu_dual_responses"] = 1;
endtask
