// writeback_same_address场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_writeback_same_address_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_writeback_same_address_sequence)
    function new(string name = "dcache_writeback_same_address_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_writeback_same_address_sequence::body();
    int before_reads;
    int target_id;
    bit [31:0] victim;
    dirty_set(0);
    cfg.write_response_enable = 0;
    access(address(0, 5));
    while (obs.writes == 0) obs.wait_cycles(1);
    victim = obs.write_samples[0].memWriteReq_payload_addr;
    before_reads = obs.reads;
    // 允许请求被流水接收或受阻；观察窗口后放行，不能在sequence里等死。
    fork
        access(victim, 0, 0, 0);
        begin
            obs.wait_cycles(32);
            record_check("same-address read not sent before write ack", obs.reads-before_reads, 0);
            cfg.write_response_enable = 1;
        end
    join
    finish_scenario();
    record_check("same-address read sent after write ack", obs.reads-before_reads, 1);
endtask
