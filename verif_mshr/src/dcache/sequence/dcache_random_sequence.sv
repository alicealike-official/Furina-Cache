// random场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_random_sequence extends dcache_scenario_sequence;
    int request_count = 4096;
    // -1为三种地址分布轮换，0均匀、1两条热点行、2同set冲突。
    int profile = -1;
    bit random_ids = 0;
    bit random_cpu_sink = 0;
    `uvm_object_utils(dcache_random_sequence)
    function new(string name = "dcache_random_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

// 按指定地址分布生成读写请求；数据由公共参考模型按CPU接受顺序检查。
task dcache_random_sequence::body();
    dcache_sequencer sequencer;
    int rounds;
    int id_start;
    int auxiliary_requests;
    int before_auxiliary;
    int tag;
    int set_index;
    int word_index;
    bit is_write;
    bit [31:0] data;
    rounds = request_count;
    auxiliary_requests = 0;
    cfg.random_memory_ready = 1;
    cfg.random_cpu_ready = random_cpu_sink;
    if (profile >= 0) cfg.continuous_cpu = 1;
    cfg.random_memory_latency = 1;
    cfg.response_order = 2;
    for (int index = 0; index < rounds; index++) begin
        // 【防御性检查】随机字段必须生成成功；三种地址分布分别命中。
        if (!std::randomize(tag, set_index, word_index, is_write, data) with {
            tag inside {[1:12]}; set_index inside {[0:31]}; word_index inside {[0:15]};
        }) `fatal("CPU stimulus randomization failed", "DCACHE_RANDOMIZE")
        case (profile < 0 ? (index / 128) % 3 : profile)
            1: begin set_index = 0; tag = 1 + tag % 2; end
            2: set_index = 1;
            default: begin end
        endcase
        if (random_ids) begin
            id_start = $urandom_range(31,0);
            for (int offset = 0; offset < 32; offset++) begin
                if (!obs.pending[(id_start+offset)%32]) begin
                    next_id = (id_start+offset)%32;
                    break;
                end
            end
        end
        access(address(set_index, tag, word_index), is_write, data, 0);
        if (index % 128 == 127) obs.wait_empty();
        // 长跑每8192笔执行一次受测脏行驱逐与后端回读，不能仅凭CPU完成宣称写回正确。
        if (request_count >= 65536 && index % 8192 == 8191) begin
            before_auxiliary = submitted;
            dirty_set(31);
            evict_set(31);
            check_evicted_set(31);
            auxiliary_requests += submitted - before_auxiliary;
        end
    end
    finish_scenario();
    record_check("required random requests", obs.requests-auxiliary_requests, request_count);
    // 两条热点行不会触发容量淘汰；其它分布必须实际发生脏写回。
    if (profile != 1) begin
        record_check("random dirty writeback occurred", obs.writes, 1, 1);
    end
    if (profile != 1) required_hits["memory_read_stall"] = 1;
    if (profile >= 0) begin
        // 【防御性检查】热点专属命中从真实接口monitor获取，不能只看请求总量。
        if (!$cast(sequencer, get_sequencer()) || sequencer.probe_monitor == null) begin
            `fatal("Random profile requires internal observation", "DCACHE_PROBE_CONFIG")
        end
        if (profile == 1) begin
            record_check("hotspot merged requests", sequencer.probe_monitor.hits["merge"], 1, 1);
            record_check("hotspot last Slot used", sequencer.probe_monitor.hits["last_slot_merge"], 1, 1);
            record_check("hotspot write-read bypass", sequencer.probe_monitor.hits["bypass_used"], 1, 1);
        end else if (profile == 2) begin
            record_check("conflict dirty eviction", sequencer.probe_monitor.hits["dirty_atomic"], 1, 1);
            record_check("conflict all ways locked", sequencer.probe_monitor.hits["all_ways_locked"], 1, 1);
            record_check("conflict WBB full then released", sequencer.probe_monitor.hits["full_wbb_response"], 1, 1);
        end
    end
    if (random_cpu_sink) begin
        required_hits["cpu_read_stall"] = 1;
        required_hits["cpu_write_stall"] = 1;
    end
endtask
