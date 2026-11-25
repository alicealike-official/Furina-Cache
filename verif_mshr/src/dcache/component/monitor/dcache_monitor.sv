class dcache_monitor extends uvm_monitor;
    virtual dcache_interface vif;
    uvm_analysis_port #(dcache_sample) monitor_port;
    `uvm_component_utils(dcache_monitor)
    function new(string name = "dcache_monitor", uvm_component parent = null);
        super.new(name, parent);
        monitor_port = new("monitor_port", this);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】接口必须来自TB顶层。
        if (!uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", vif)) begin
            `fatal("DCache interface missing", "DCACHE_CONFIG")
        end
    endfunction
    task run_phase(uvm_phase phase);
        forever begin
            dcache_sample sample;
            @(vif.mon_cb);
            sample = dcache_sample::type_id::create("sample");
            sample.rst_n = vif.mon_cb.rst_n;
            // CPU请求与返回，供事务配对和模型比较。
            sample.cpu_valid = vif.mon_cb.cpu_valid;
            sample.cpu_ready = vif.mon_cb.cpu_ready;
            sample.cpu_payload_addr = vif.mon_cb.cpu_payload_addr;
            sample.cpu_payload_wrEn = vif.mon_cb.cpu_payload_wrEn;
            sample.cpu_payload_wData = vif.mon_cb.cpu_payload_wData;
            sample.cpu_payload_id = vif.mon_cb.cpu_payload_id;
            sample.cpuReadResp_valid = vif.mon_cb.cpuReadResp_valid;
            sample.cpuReadResp_ready = vif.mon_cb.cpuReadResp_ready;
            sample.cpuReadResp_payload_rData = vif.mon_cb.cpuReadResp_payload_rData;
            sample.cpuReadResp_payload_id = vif.mon_cb.cpuReadResp_payload_id;
            sample.cpuWriteResp_valid = vif.mon_cb.cpuWriteResp_valid;
            sample.cpuWriteResp_ready = vif.mon_cb.cpuWriteResp_ready;
            sample.cpuWriteResp_payload_id = vif.mon_cb.cpuWriteResp_payload_id;
            // 整行内存接口，供稀疏内存代理及模型比较。
            sample.memReadReq_valid = vif.mon_cb.memReadReq_valid;
            sample.memReadReq_ready = vif.mon_cb.memReadReq_ready;
            sample.memReadReq_payload_addr = vif.mon_cb.memReadReq_payload_addr;
            sample.memReadReq_payload_id = vif.mon_cb.memReadReq_payload_id;
            sample.memWriteReq_valid = vif.mon_cb.memWriteReq_valid;
            sample.memWriteReq_ready = vif.mon_cb.memWriteReq_ready;
            sample.memWriteReq_payload_addr = vif.mon_cb.memWriteReq_payload_addr;
            sample.memWriteReq_payload_wData = vif.mon_cb.memWriteReq_payload_wData;
            sample.memWriteReq_payload_id = vif.mon_cb.memWriteReq_payload_id;
            sample.memReadResp_valid = vif.mon_cb.memReadResp_valid;
            sample.memReadResp_ready = vif.mon_cb.memReadResp_ready;
            sample.memReadResp_payload_rData = vif.mon_cb.memReadResp_payload_rData;
            sample.memReadResp_payload_id = vif.mon_cb.memReadResp_payload_id;
            sample.memWriteResp_valid = vif.mon_cb.memWriteResp_valid;
            sample.memWriteResp_ready = vif.mon_cb.memWriteResp_ready;
            sample.memWriteResp_payload_id = vif.mon_cb.memWriteResp_payload_id;
            monitor_port.write(sample);
        end
    endtask
endclass
