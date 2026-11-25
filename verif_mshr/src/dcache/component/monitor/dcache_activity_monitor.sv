// 只使用顶层IO记录实际接受/完成及场景证据；不访问内部Entry、FIFO或DE层级。
class dcache_activity_monitor extends uvm_subscriber #(dcache_sample);
    event sampled;
    longint cycle;
    int hits[string];
    int cpu_burst, max_cpu_burst;
    longint unsigned cpu_cycles[$];
    int requests, responses, reads, writes, read_acks, write_acks;
    bit pending[32];
    bit [31:0] expected_read[32];
    int read_inflight[$];
    int write_inflight[$];
    longint read_cycle[16];
    longint write_cycle[16];
    int read_delays[int];
    int write_delays[int];
    dcache_sample write_samples[$];
    dcache_sample last_sample;
    // 原C++ SparseMemory保存CPU接受顺序的期望数据，独立于实际后端MEM；不模拟Cache行为。
    dcache_memory_store architecture;
    `uvm_component_utils(dcache_activity_monitor)
    function new(string name = "dcache_activity_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        architecture = dcache_memory_store::type_id::create("architecture");
        architecture.initialize();
    endfunction
    // 累加实际场景事件，不以sequence调用次数代替命中。
    function void count(string name);
        if (!hits.exists(name)) hits[name] = 0;
        hits[name]++;
    endfunction
    // 沿前采样驱动CPU顺序期望与内存事件统计，然后唤醒等待的sequence。
    function void write(dcache_sample t);
        last_sample = t;
        if (!t.rst_n) return;
        cycle++;
        if (t.cpu_valid && t.cpu_ready) begin
            cpu_burst++;
            if (cpu_burst > 1) count("consecutive_cpu");
            if (cpu_burst > max_cpu_burst) max_cpu_burst = cpu_burst;
        end else cpu_burst = 0;
        record_cpu(t);
        record_memory(t);
        if (t.cpu_valid && !t.cpu_ready) count("cpu_stall");
        if (t.cpuReadResp_valid && !t.cpuReadResp_ready) count("cpu_read_stall");
        if (t.cpuWriteResp_valid && !t.cpuWriteResp_ready) count("cpu_write_stall");
        if (t.memReadReq_valid && !t.memReadReq_ready) count("memory_read_stall");
        if (t.memWriteReq_valid && !t.memWriteReq_ready) count("memory_write_stall");
        if (t.memReadReq_valid && t.memReadReq_ready && t.memWriteReq_valid && t.memWriteReq_ready) count("dual_requests");
        if (t.memReadResp_valid && t.memReadResp_ready && t.memWriteResp_valid && t.memWriteResp_ready) count("dual_responses");
        if (t.cpu_valid && t.cpu_ready && t.memReadResp_valid && t.memReadResp_ready &&
            t.memWriteResp_valid && t.memWriteResp_ready) count("cpu_dual_responses");
        ->sampled;
    endfunction
    // CPU写按接受顺序更新架构期望，读在接受时保存值；后续写不能改动旧读期望。
    function void record_cpu(dcache_sample sample);
        bit [511:0] line;
        bit [31:0] block;
        int word_index;
        if (sample.cpu_valid && sample.cpu_ready) begin
            if (pending[sample.cpu_payload_id]) begin
                `fatal("Stimulus reuses pending CPU ID", "DCACHE_STIMULUS_ID")
            end
            block = {sample.cpu_payload_addr[31:6], 6'b0};
            word_index = sample.cpu_payload_addr[5:2];
            // read_line/write_line经dcache_mem_* DPI使用原C++ SparseMemory。
            architecture.read_line(block, line);
            expected_read[sample.cpu_payload_id] = line[word_index*32 +: 32];
            if (sample.cpu_payload_wrEn) begin
                line[word_index*32 +: 32] = sample.cpu_payload_wData;
                architecture.write_line(block, line);
            end
            pending[sample.cpu_payload_id] = 1;
            cpu_cycles.push_back(cycle);
            requests++;
        end
        if (sample.cpuReadResp_valid && sample.cpuReadResp_ready) begin
            if (sample.cpuReadResp_payload_rData !== expected_read[sample.cpuReadResp_payload_id]) begin
                `error($sformatf("Read id=%0d data=%h expected=%h", sample.cpuReadResp_payload_id,
                    sample.cpuReadResp_payload_rData, expected_read[sample.cpuReadResp_payload_id]), "DCACHE_ARCH_DATA")
            end
            pending[sample.cpuReadResp_payload_id] = 0;
            responses++;
        end
        if (sample.cpuWriteResp_valid && sample.cpuWriteResp_ready) begin
            pending[sample.cpuWriteResp_payload_id] = 0;
            responses++;
        end
    endfunction
    // 按各自ID记录读写在途、实际延迟和乱序；写回快照供case独立核对版本。
    function void record_memory(dcache_sample sample);
        int delay_cycles;
        if (sample.memReadResp_valid && sample.memReadResp_ready) begin
            retire_id(read_inflight, sample.memReadResp_payload_id, "read_reorder");
            delay_cycles = int'(cycle - read_cycle[sample.memReadResp_payload_id]);
            if (!read_delays.exists(delay_cycles)) read_delays[delay_cycles] = 0;
            read_delays[delay_cycles]++;
            read_acks++;
        end
        if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
            retire_id(write_inflight, sample.memWriteResp_payload_id, "write_reorder");
            delay_cycles = int'(cycle - write_cycle[sample.memWriteResp_payload_id]);
            if (!write_delays.exists(delay_cycles)) write_delays[delay_cycles] = 0;
            write_delays[delay_cycles]++;
            write_acks++;
        end
        if (sample.memReadReq_valid && sample.memReadReq_ready) begin
            read_inflight.push_back(sample.memReadReq_payload_id);
            read_cycle[sample.memReadReq_payload_id] = cycle;
            reads++;
        end
        if (sample.memWriteReq_valid && sample.memWriteReq_ready) begin
            write_inflight.push_back(sample.memWriteReq_payload_id);
            write_cycle[sample.memWriteReq_payload_id] = cycle;
            write_samples.push_back(sample);
            writes++;
        end
    endfunction
    // 删除实际已响应ID，非队首完成时记录乱序；只记录事件，不预测仲裁。
    function void retire_id(ref int queue[$], input int id, input string label);
        foreach (queue[index]) begin
            if (queue[index] == id) begin
                if (index != 0) count(label);
                queue.delete(index);
                return;
            end
        end
        `error("Response has no observed in-flight ID", "DCACHE_RESPONSE_OWNER")
    endfunction
    // 所有等待以实际采样拍为单位，受test全局watchdog保护。
    task wait_cycles(int count_cycles);
        repeat (count_cycles) @sampled;
    endtask
    // 等待当前已接受CPU请求和内存义务完成，不声称脏Cache已写回。
    task wait_empty();
        wait_cycles(4);
        while (requests != responses || reads != read_acks || writes != write_acks) @sampled;
        wait_cycles(4);
    endtask
    function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        architecture.close();
    endfunction
endclass
