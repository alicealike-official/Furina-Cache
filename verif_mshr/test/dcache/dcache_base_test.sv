class dcache_base_test extends uvm_test;
    dcache_environment env;
    dcache_config cfg;
    clk_rst_config clock_cfg;
    virtual dcache_interface vif;
    `uvm_component_utils(dcache_base_test)
    function new(string name = "dcache_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】时钟仅由TB创建并逐级传递。
        if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clock_cfg) ||
            !uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", vif)) begin
            `fatal("Top-level configuration missing", "DCACHE_CONFIG")
        end
        cfg = dcache_config::type_id::create("cfg");
        uvm_config_db #(dcache_config)::set(this, "env", "dcache_config", cfg);
        uvm_config_db #(clk_rst_config)::set(this, "env", "clk_rst_config", clock_cfg);
        env = dcache_environment::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        fork
            begin
                wait (vif.rst_n === 1'b1);
                repeat (2) @(negedge vif.clk);
                run_sequence();
                wait_for_drain();
            end
            begin
                repeat (cfg.timeout_cycles) @(negedge vif.clk);
                `fatal("DCache test cycle timeout", "DCACHE_TIMEOUT")
            end
        join_any
        disable fork;
        phase.drop_objection(this);
    endtask
    // 默认无testname只运行空态和时钟复位检查，不偷偷提交CPU请求。
    virtual task run_sequence();
        repeat (10) @(negedge vif.clk);
    endtask
    // 等待已接受事务全部完成，并多观察四拍，发现收尾后的额外响应。
    task wait_for_drain();
        repeat (4) @(negedge vif.clk);
        while (!env.is_idle()) @(negedge vif.clk);
        repeat (4) @(negedge vif.clk);
    endtask
    // 公共精确计数比较，具体case只给目标值。
    function void check_count(string label, int actual, int expected);
        if (actual != expected) begin
            `error($sformatf("%s actual=%0d expected=%0d", label, actual, expected), "DCACHE_TEST_COUNT")
        end
    endfunction
    function void report_phase(uvm_phase phase);
        uvm_report_server server;
        super.report_phase(phase);
        server = uvm_report_server::get_server();
        if (server.get_severity_count(UVM_ERROR) == 0 && server.get_severity_count(UVM_FATAL) == 0) begin
            `info("DCache framework completed", "DCACHE_TEST_PASS")
        end else begin
            `info("DCache framework failed", "DCACHE_TEST_FAIL")
        end
    endfunction
endclass
