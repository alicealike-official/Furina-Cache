class wbb_base_test extends uvm_test;
    wbb_environment env;
    virtual wbb_interface vif;
    wbb_config cfg;

    `uvm_component_utils(wbb_base_test)

    function new(string name = "wbb_base_test",
        uvm_component parent = null);
        super.new(name, parent);
        if (get_parent() == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern virtual function void report_phase(uvm_phase phase);

endclass

function void wbb_base_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg)) begin
        cfg = wbb_config::type_id::create("cfg");
    end
    uvm_config_db #(wbb_config)::set(this, "env", "wbb_config", cfg);
    env = wbb_environment::type_id::create("env", this);
endfunction

task wbb_base_test::run_phase(uvm_phase phase);
    phase.raise_objection(this);
    fork
        begin
            wait (vif.rst_n === 1'b1);
            repeat (2) @(negedge vif.clk);
            run_sequence();
            repeat (4) @(negedge vif.clk);
            while (!env.is_idle()) begin
                @(negedge vif.clk);
            end
        end
        begin
            repeat (cfg.timeout_cycles) @(negedge vif.clk);
            `fatal("WBB test watchdog timeout", "WBB_TIMEOUT")
        end
    join_any
    disable fork;
    phase.drop_objection(this);
endtask

// 派生 test 可覆盖此 task 来启动自己的 sequence。
// 基础实现仅等待 10 个时钟下降沿，供环境启动与空闲观察使用，不发送 WBB 请求。
task wbb_base_test::run_sequence();
    // Framework startup only; no WBB transactions or functional case.
    repeat (10) @(negedge vif.clk);
endtask

function void wbb_base_test::report_phase(uvm_phase phase);
    uvm_report_server server;
    super.report_phase(phase);
    server = uvm_report_server::get_server();
    if (server.get_severity_count(UVM_ERROR) == 0 && server.get_severity_count(UVM_FATAL) == 0) begin
        `info("Framework startup completed with C++ WBB and sparse-memory models; no functional case executed", "WBB_FRAMEWORK_READY")
    end else begin
        `info("Framework startup failed; inspect UVM_ERROR/UVM_FATAL", "WBB_FRAMEWORK_FAIL")
    end
endfunction
