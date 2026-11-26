class dcache_driver extends uvm_driver #(dcache_transaction);
    virtual dcache_interface vif;
    dcache_config cfg;
    `uvm_component_utils(dcache_driver)
    function new(string name = "dcache_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】接口和配置由上层提供。
        if (!uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", vif) ||
            !uvm_config_db #(dcache_config)::get(this, "", "dcache_config", cfg)) begin
            `fatal("CPU driver configuration missing", "DCACHE_CONFIG")
        end
    endfunction
    task run_phase(uvm_phase phase);
        vif.cpu_valid <= 0;
        vif.cpu_payload_addr <= 0;
        vif.cpu_payload_wrEn <= 0;
        vif.cpu_payload_wData <= 0;
        vif.cpu_payload_id <= 0;
        wait (vif.rst_n === 1'b1);
        forever begin
            seq_item_port.get_next_item(req);
            wait (vif.rst_n === 1'b1);
            fork : request_or_reset
                begin
                    drive_request(req);
                end
                begin
                    @(negedge vif.rst_n);
                    if (!cfg.allow_reset_cancellation) begin
                        `fatal("Active request reset requires cancellation enabled", "TB_RESET")
                    end
                    drive_idle();
                end
            join_any
            disable request_or_reset;
            seq_item_port.item_done();
        end
    endtask
    // CPU源独占这些信号，异步复位时及时撤销有效请求。
    task drive_idle();
        vif.cpu_valid <= 0;
        vif.cpu_payload_addr <= 0;
        vif.cpu_payload_wrEn <= 0;
        vif.cpu_payload_wData <= 0;
        vif.cpu_payload_id <= 0;
    endtask
    // 在下降沿呈现请求，所有字段保持到握手；字段与随机化均来自sequence。
    task drive_request(dcache_transaction item);
        // 【激励合法性检查】CPU请求必须整字对齐。
        if (item.addr[1:0] != 0) begin
            `fatal("Unaligned CPU stimulus", "DCACHE_REQUEST")
        end
        @(negedge vif.clk);
        vif.cpu_valid <= !item.idle_payload;
        vif.cpu_payload_addr <= item.addr;
        vif.cpu_payload_wrEn <= item.is_write;
        vif.cpu_payload_wData <= item.data;
        vif.cpu_payload_id <= item.id;
        if (item.idle_payload) @(vif.mon_cb);
        else wait_acceptance();
        // 连续模式在接受后返回，下一项可在下一个下降沿呈现，不额外插入空拍。
        if (!cfg.continuous_cpu) @(negedge vif.clk);
        vif.cpu_valid <= 0;
    endtask
    // 按采样拍等待请求被接受；超时或运行中复位明确报告，不自行丢请求。
    task wait_acceptance();
        repeat (cfg.request_timeout_cycles) begin
            @(vif.mon_cb);
            if (vif.mon_cb.rst_n !== 1'b1) begin
                `fatal("Reset during active CPU request", "DCACHE_RESET")
            end
            if (vif.mon_cb.cpu_ready === 1'b1) return;
        end
        `fatal("CPU request acceptance timeout", "DCACHE_TIMEOUT")
    endtask
endclass
