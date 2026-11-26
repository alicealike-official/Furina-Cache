class dcache_scoreboard extends uvm_subscriber #(dcache_compare_item);
    int cycles, requests, read_responses, write_responses;
    bit pending[32];
    bit write_kind[32];
    int cancelled_requests;
    `uvm_component_utils(dcache_scoreboard)
    function new(string name = "dcache_scoreboard", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 比较原C++预测与沿前IO，再按CPU ID记录实际请求和响应。
    function void write(dcache_compare_item t);
        if (!t.actual.rst_n) begin
            reset_history();
            return;
        end
        cycles++;
        compare_outputs(t.actual, t.expected);
        record_cpu_events(t.actual);
    endfunction
    // valid逐拍比较；只有实际和期望均有效时才比较载荷，避免把无效X或旧值当数据错误。
    function void compare_outputs(dcache_sample actual, dcache_sample expected);
        if (1 && actual.cpu_ready !== expected.cpu_ready) begin
            `error($sformatf("cpu_ready: actual=%h expected=%h", actual.cpu_ready, expected.cpu_ready), "DCACHE_MODEL_MISMATCH")
        end
        if (1 && actual.cpuReadResp_valid !== expected.cpuReadResp_valid) begin
            `error($sformatf("cpuReadResp_valid: actual=%h expected=%h", actual.cpuReadResp_valid, expected.cpuReadResp_valid), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.cpuReadResp_valid && actual.cpuReadResp_valid && actual.cpuReadResp_payload_rData !== expected.cpuReadResp_payload_rData) begin
            `error($sformatf("cpuReadResp_payload_rData: actual=%h expected=%h", actual.cpuReadResp_payload_rData, expected.cpuReadResp_payload_rData), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.cpuReadResp_valid && actual.cpuReadResp_valid && actual.cpuReadResp_payload_id !== expected.cpuReadResp_payload_id) begin
            `error($sformatf("cpuReadResp_payload_id: actual=%h expected=%h", actual.cpuReadResp_payload_id, expected.cpuReadResp_payload_id), "DCACHE_MODEL_MISMATCH")
        end
        if (1 && actual.cpuWriteResp_valid !== expected.cpuWriteResp_valid) begin
            `error($sformatf("cpuWriteResp_valid: actual=%h expected=%h", actual.cpuWriteResp_valid, expected.cpuWriteResp_valid), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.cpuWriteResp_valid && actual.cpuWriteResp_valid && actual.cpuWriteResp_payload_id !== expected.cpuWriteResp_payload_id) begin
            `error($sformatf("cpuWriteResp_payload_id: actual=%h expected=%h", actual.cpuWriteResp_payload_id, expected.cpuWriteResp_payload_id), "DCACHE_MODEL_MISMATCH")
        end
        if (1 && actual.memReadReq_valid !== expected.memReadReq_valid) begin
            `error($sformatf("memReadReq_valid: actual=%h expected=%h", actual.memReadReq_valid, expected.memReadReq_valid), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.memReadReq_valid && actual.memReadReq_valid && actual.memReadReq_payload_addr !== expected.memReadReq_payload_addr) begin
            `error($sformatf("memReadReq_payload_addr: actual=%h expected=%h", actual.memReadReq_payload_addr, expected.memReadReq_payload_addr), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.memReadReq_valid && actual.memReadReq_valid && actual.memReadReq_payload_id !== expected.memReadReq_payload_id) begin
            `error($sformatf("memReadReq_payload_id: actual=%h expected=%h", actual.memReadReq_payload_id, expected.memReadReq_payload_id), "DCACHE_MODEL_MISMATCH")
        end
        if (1 && actual.memWriteReq_valid !== expected.memWriteReq_valid) begin
            `error($sformatf("memWriteReq_valid: actual=%h expected=%h", actual.memWriteReq_valid, expected.memWriteReq_valid), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.memWriteReq_valid && actual.memWriteReq_valid && actual.memWriteReq_payload_addr !== expected.memWriteReq_payload_addr) begin
            `error($sformatf("memWriteReq_payload_addr: actual=%h expected=%h", actual.memWriteReq_payload_addr, expected.memWriteReq_payload_addr), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.memWriteReq_valid && actual.memWriteReq_valid && actual.memWriteReq_payload_wData !== expected.memWriteReq_payload_wData) begin
            `error($sformatf("memWriteReq_payload_wData: actual=%h expected=%h", actual.memWriteReq_payload_wData, expected.memWriteReq_payload_wData), "DCACHE_MODEL_MISMATCH")
        end
        if (expected.memWriteReq_valid && actual.memWriteReq_valid && actual.memWriteReq_payload_id !== expected.memWriteReq_payload_id) begin
            `error($sformatf("memWriteReq_payload_id: actual=%h expected=%h", actual.memWriteReq_payload_id, expected.memWriteReq_payload_id), "DCACHE_MODEL_MISMATCH")
        end
    endfunction
    // 沿前CPU ID不得重复；两种响应可同拍，但必须各自匹配已接受请求的类型。
    function void record_cpu_events(dcache_sample sample);
        if (sample.cpu_valid && sample.cpu_ready) begin
            if (pending[sample.cpu_payload_id]) begin
                `fatal("CPU ID reused before completion", "DCACHE_CPU_ID")
            end
            pending[sample.cpu_payload_id] = 1;
            write_kind[sample.cpu_payload_id] = sample.cpu_payload_wrEn;
            requests++;
            `info($sformatf("cycle=%0d request id=%0d write=%b addr=%h data=%h", cycles,
                sample.cpu_payload_id, sample.cpu_payload_wrEn, sample.cpu_payload_addr,
                sample.cpu_payload_wData), "DCACHE_CPU_TRACE")
        end
        if (sample.cpuReadResp_valid && sample.cpuReadResp_ready) begin
            complete_cpu(sample.cpuReadResp_payload_id, 0);
            read_responses++;
            `info($sformatf("cycle=%0d read_response id=%0d data=%h", cycles,
                sample.cpuReadResp_payload_id, sample.cpuReadResp_payload_rData), "DCACHE_CPU_TRACE")
        end
        if (sample.cpuWriteResp_valid && sample.cpuWriteResp_ready) begin
            complete_cpu(sample.cpuWriteResp_payload_id, 1);
            write_responses++;
            `info($sformatf("cycle=%0d write_response id=%0d", cycles,
                sample.cpuWriteResp_payload_id), "DCACHE_CPU_TRACE")
        end
    endfunction
    // 一次CPU响应只完成同ID、同类型的请求，不按全局FIFO强制跨行顺序。
    function void complete_cpu(int id, bit is_write);
        if (!pending[id] || write_kind[id] != is_write) begin
            `error($sformatf("Unexpected CPU response id=%0d write=%0b", id, is_write), "DCACHE_CPU_RESPONSE")
        end
        pending[id] = 0;
    endfunction
    // 只检查CPU侧未完成请求，不能把它当作所有脏行已经写回的证明。
    function bit is_idle();
        foreach (pending[id]) begin
            if (pending[id]) return 0;
        end
        return 1;
    endfunction
    // 只取消仍在等待CPU响应的ID，保留已完成计数和已报错误。
    function void reset_history();
        foreach (pending[id]) begin
            if (pending[id]) cancelled_requests++;
            pending[id] = 0;
        end
    endfunction
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (!is_idle() || requests != read_responses + write_responses + cancelled_requests || cycles == 0) begin
            `error("CPU requests did not complete or no samples checked", "DCACHE_DRAIN")
        end
    endfunction
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `info($sformatf("cycles=%0d requests=%0d read_responses=%0d write_responses=%0d",
            cycles, requests, read_responses, write_responses), "DCACHE_COUNTS")
    endfunction
endclass
