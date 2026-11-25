class dcache_predictor extends uvm_subscriber #(dcache_sample);
    uvm_analysis_port #(dcache_compare_item) compare_port;
    // 原C++ CacheTop实例，非DUT层级句柄，算法不在SV中重写。
    protected chandle handle;
    `uvm_component_utils(dcache_predictor)
    function new(string name = "dcache_predictor", uvm_component parent = null);
        super.new(name, parent);
        compare_port = new("compare_port", this);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        handle = dcache_ref_create();
        if (handle == null) begin
            `fatal(dcache_last_error(), "DCACHE_MODEL")
        end
    endfunction
    // 将同一拍输入交给原CacheTop，经DPI执行eval/tick，输出与原IO快照配对发布。
    function void write(dcache_sample t);
        int unsigned inputs[SAMPLE_WORDS];
        int unsigned outputs[SAMPLE_WORDS];
        dcache_compare_item item;
        // 【防御性检查】先检查四态输入，再交给两态C++，避免未知输入被静默转换。
        if ($isunknown({t.rst_n, t.cpu_valid, t.cpuReadResp_ready, t.cpuWriteResp_ready,
            t.memReadReq_ready, t.memWriteReq_ready, t.memReadResp_valid, t.memWriteResp_valid}) ||
            (t.cpu_valid && $isunknown({t.cpu_payload_addr, t.cpu_payload_id, t.cpu_payload_wrEn,
                t.cpu_payload_wData})) ||
            (t.memReadResp_valid && $isunknown({t.memReadResp_payload_id, t.memReadResp_payload_rData})) ||
            (t.memWriteResp_valid && $isunknown(t.memWriteResp_payload_id))) begin
            `fatal("Unknown input before C++ conversion", "DCACHE_INPUT_X")
        end
        item = dcache_compare_item::type_id::create("item");
        item.actual = t;
        inputs[0] = t.cpu_valid;
        inputs[2] = t.cpu_payload_addr;
        inputs[3] = t.cpu_payload_wrEn;
        inputs[4] = t.cpu_payload_wData;
        inputs[5] = t.cpu_payload_id;
        inputs[7] = t.cpuReadResp_ready;
        inputs[11] = t.cpuWriteResp_ready;
        inputs[14] = t.memReadReq_ready;
        inputs[18] = t.memWriteReq_ready;
        inputs[37] = t.memReadResp_valid && t.memReadResp_ready;
        for (int word = 0; word < 16; word++) inputs[39 + word] = t.memReadResp_payload_rData[word*32 +: 32];
        inputs[55] = t.memReadResp_payload_id;
        inputs[56] = t.memWriteResp_valid && t.memWriteResp_ready;
        inputs[58] = t.memWriteResp_payload_id;
        if (!dcache_ref_step(handle, !t.rst_n, inputs, outputs)) begin
            `fatal(dcache_last_error(), "DCACHE_MODEL")
        end
        if (!t.rst_n) return;
        item.expected.cpu_ready = 1'(outputs[1]);
        item.expected.cpuReadResp_valid = 1'(outputs[6]);
        item.expected.cpuReadResp_payload_rData = 32'(outputs[8]);
        item.expected.cpuReadResp_payload_id = 5'(outputs[9]);
        item.expected.cpuWriteResp_valid = 1'(outputs[10]);
        item.expected.cpuWriteResp_payload_id = 5'(outputs[12]);
        item.expected.memReadReq_valid = 1'(outputs[13]);
        item.expected.memReadReq_payload_addr = 32'(outputs[15]);
        item.expected.memReadReq_payload_id = 4'(outputs[16]);
        item.expected.memWriteReq_valid = 1'(outputs[17]);
        item.expected.memWriteReq_payload_addr = 32'(outputs[19]);
        for (int word = 0; word < 16; word++) item.expected.memWriteReq_payload_wData[word*32 +: 32] = outputs[20 + word];
        item.expected.memWriteReq_payload_id = 4'(outputs[36]);
        compare_port.write(item);
    endfunction
    function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        // dcache_ref_destroy释放RefModel/Cache/CacheTop.hpp实例。
        dcache_ref_destroy(handle);
    endfunction
endclass
