// 内存代理负责总线控制，数据存储使用原C++ SparseMemory，读写两方向独立。
class dcache_memory_driver extends uvm_subscriber #(dcache_sample);
    typedef struct packed {
        bit [3:0] id;
        bit [511:0] data;
        longint unsigned due_cycle;
    } pending_t;
    virtual dcache_interface vif;
    dcache_config cfg;
    // C++ SparseMemory的SV封装；不是SV重新实现的内存模型。
    dcache_memory_store memory;
    pending_t reads[$];
    pending_t writes[$];
    bit read_ids[16];
    bit write_ids[16];
    longint unsigned cycle;
    int read_requests, read_responses, write_requests, write_responses;
    bit read_presented, write_presented;
    `uvm_component_utils(dcache_memory_driver)
    function new(string name = "dcache_memory_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】模型封装与配置由环境统一提供。
        if (!uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", vif) ||
            !uvm_config_db #(dcache_config)::get(this, "", "dcache_config", cfg) ||
            !uvm_config_db #(dcache_memory_store)::get(this, "", "memory", memory)) begin
            `fatal("Memory dependencies missing", "DCACHE_CONFIG")
        end
    endfunction
    // monitor发布同一沿前快照；先完成旧响应，再接受新请求。
    function void write(dcache_sample t);
        if (!t.rst_n) begin
            if (!is_idle()) begin
                `fatal("Active reset cancellation is not defined", "DCACHE_RESET")
            end
            return;
        end
        cycle++;
        complete_responses(t);
        accept_reads(t);
        accept_writes(t);
    endfunction
    // 只有响应握手才删除队首与ID；背压期间保持同一对象。
    function void complete_responses(dcache_sample sample);
        pending_t response;
        if (sample.memReadResp_valid && sample.memReadResp_ready) begin
            if (reads.size() == 0 || reads[0].id != sample.memReadResp_payload_id) begin
                `fatal("Read response has no matching request", "DCACHE_MEMORY")
            end
            response = reads.pop_front();
            read_ids[response.id] = 0;
            read_presented = 0;
            read_responses++;
        end
        if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
            if (writes.size() == 0 || writes[0].id != sample.memWriteResp_payload_id) begin
                `fatal("Write response has no matching request", "DCACHE_MEMORY")
            end
            response = writes.pop_front();
            write_ids[response.id] = 0;
            write_presented = 0;
            write_responses++;
        end
    endfunction
    // 实际读请求握手时，从原C++后端MEM保存整行快照，后续只返回该快照。
    function void accept_reads(dcache_sample sample);
        pending_t request;
        if (!(sample.memReadReq_valid && sample.memReadReq_ready)) return;
        if (sample.memReadReq_payload_id >= MSHR_ENTRIES || read_ids[sample.memReadReq_payload_id]) begin
            `fatal("Invalid/duplicate read ID", "DCACHE_READ_ID")
        end
        request.id = sample.memReadReq_payload_id;
        request.due_cycle = cycle + (cfg.random_memory_latency ? $urandom_range(cfg.max_latency_cycles, 1) : cfg.read_latency_cycles);
        // read_line经dcache_mem_read DPI访问RefModel/MEM/SparseMemory.hpp。
        memory.read_line(sample.memReadReq_payload_addr, request.data);
        reads.push_back(request);
        read_ids[request.id] = 1;
        read_requests++;
    endfunction
    // 写请求握手时更新后端MEM，并登记未来的写响应；CPU写不会直接更新后端。
    function void accept_writes(dcache_sample sample);
        pending_t request;
        if (!(sample.memWriteReq_valid && sample.memWriteReq_ready)) return;
        if (sample.memWriteReq_payload_id >= WBB_ENTRIES || write_ids[sample.memWriteReq_payload_id]) begin
            `fatal("Invalid/duplicate write ID", "DCACHE_WRITE_ID")
        end
        request.id = sample.memWriteReq_payload_id;
        request.due_cycle = cycle + (cfg.random_memory_latency ? $urandom_range(cfg.max_latency_cycles, 1) : cfg.write_latency_cycles);
        request.data = sample.memWriteReq_payload_wData;
        // write_line经dcache_mem_write DPI更新原C++ SparseMemory。
        memory.write_line(sample.memWriteReq_payload_addr, request.data);
        writes.push_back(request);
        write_ids[request.id] = 1;
        write_requests++;
    endfunction
    task run_phase(uvm_phase phase);
        drive_idle();
        forever begin
            @(negedge vif.clk);
            if (!vif.rst_n) drive_idle();
            else begin
                // 【防御性检查】当前普通协议至少一拍响应，零拍不支持。
                if (cfg.read_latency_cycles < 1 || cfg.write_latency_cycles < 1) begin
                    `fatal("Memory latency must be positive cycles", "DCACHE_CONFIG")
                end
                drive_acceptance();
                drive_responses();
            end
        end
    endtask
    // 启动复位期间只驱动本agent拥有的内存信号。
    task drive_idle();
        vif.memReadReq_ready <= 0;
        vif.memWriteReq_ready <= 0;
        vif.memReadResp_valid <= 0;
        vif.memWriteResp_valid <= 0;
        vif.memReadResp_payload_rData <= 0;
        vif.memReadResp_payload_id <= 0;
        vif.memWriteResp_payload_id <= 0;
    endtask
    // 容量足够才接受新内存请求。
    task drive_acceptance();
        vif.memReadReq_ready <= cfg.read_request_enable && reads.size() < MSHR_ENTRIES &&
            (!cfg.random_memory_ready || $urandom_range(99, 0) < cfg.ready_percent);
        vif.memWriteReq_ready <= cfg.write_request_enable && writes.size() < WBB_ENTRIES &&
            (!cfg.random_memory_ready || $urandom_range(99, 0) < cfg.ready_percent);
    endtask
    // FIFO队首到期后呈现；一旦呈现就保持到握手，开关只能阻止新的响应。
    task drive_responses();
        if (!read_presented && cfg.read_response_enable && cycle + 1 >= cfg.read_response_not_before_cycle) select_response(reads);
        if (!write_presented && cfg.write_response_enable && cycle + 1 >= cfg.write_response_not_before_cycle) select_response(writes);
        if (reads.size() > 0 && cfg.read_response_enable && cycle + 1 >= cfg.read_response_not_before_cycle && cycle + 1 >= reads[0].due_cycle) read_presented = 1;
        if (writes.size() > 0 && cfg.write_response_enable && cycle + 1 >= cfg.write_response_not_before_cycle && cycle + 1 >= writes[0].due_cycle) write_presented = 1;
        vif.memReadResp_valid <= read_presented;
        vif.memWriteResp_valid <= write_presented;
        if (read_presented) begin
            vif.memReadResp_payload_id <= reads[0].id;
            vif.memReadResp_payload_rData <= reads[0].data;
        end
        if (write_presented) vif.memWriteResp_payload_id <= writes[0].id;
        if (!read_presented) begin
            vif.memReadResp_payload_id <= cfg.idle_response_id;
            vif.memReadResp_payload_rData <= cfg.idle_response_data;
        end
        if (!write_presented) vif.memWriteResp_payload_id <= cfg.idle_response_id;
    endtask
    // 未呈现时按策略选一个已到期项到队首；呈现后不再重排，保证反压保持。
    function void select_response(ref pending_t queue[$]);
        int candidates[$];
        int selected;
        pending_t item;
        // 【防御性检查】策略及随机范围必须合法。
        if (cfg.response_order < 0 || cfg.response_order > 2 || cfg.ready_percent > 100 ||
            cfg.ready_percent < 1 || cfg.max_latency_cycles < 1) begin
            `fatal("Invalid memory random configuration", "DCACHE_CONFIG")
        end
        if (cfg.response_order == 0) return;
        foreach (queue[index]) begin
            if (cycle + 1 >= queue[index].due_cycle) candidates.push_back(index);
        end
        if (candidates.size() == 0) return;
        selected = cfg.response_order == 1 ? candidates[$] : candidates[$urandom_range(candidates.size()-1, 0)];
        item = queue[selected];
        queue.delete(selected);
        queue.push_front(item);
    endfunction
    // 只判断接口上已接受的内存义务是否全部完成，不要求脏Cache内容已经写回。
    function bit is_idle();
        return reads.size() == 0 && writes.size() == 0 && !read_presented && !write_presented;
    endfunction
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (!is_idle() || read_requests != read_responses || write_requests != write_responses) begin
            `error("Memory transactions did not drain", "DCACHE_DRAIN")
        end
    endfunction
endclass
