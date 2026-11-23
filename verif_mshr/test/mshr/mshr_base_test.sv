class mshr_base_test extends uvm_test;
    mshr_environment env;
    virtual mshr_interface vif;
    mshr_config cfg;
    protected clk_rst_config clk_cfg;

    `uvm_component_utils(mshr_base_test)

    function new(string name = "mshr_base_test", uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (get_parent() == null) begin
            `fatal("This component's parent cannot be null")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern task wait_for_drain();
    extern function void require_active_agent();
    extern function void check_count(string name, int actual, int expected);
    extern function void check_counts(int allocations, int merges, int replays);
    extern virtual function void report_phase(uvm_phase phase);
endclass

function void mshr_base_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", vif)) begin
        `fatal("MSHR interface missing", "MSHR_CONFIG")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clk_cfg) || clk_cfg == null) begin
        `fatal("TB top must provide clk_rst_config", "CLK_CONFIG")
    end
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg)) begin
        cfg = mshr_config::type_id::create("cfg");
    end
    // 【防御性检查】配置对象及总等待预算必须有效。
    if (cfg == null || cfg.timeout_cycles == 0) begin
        `fatal("Invalid MSHR config or watchdog", "MSHR_CONFIG")
    end
    uvm_config_db #(mshr_config)::set(this, "env", "mshr_config", cfg);
    uvm_config_db #(clk_rst_config)::set(this, "env", "clk_rst_config", clk_cfg);
    env = mshr_environment::type_id::create("env", this);
endfunction

task mshr_base_test::run_phase(uvm_phase phase);
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
            `fatal("MSHR global cycle watchdog expired", "MSHR_TIMEOUT")
        end
    join_any
    disable fork;
    phase.drop_objection(this);
endtask

// 默认只启动时钟、复位和空态检查；不指定testname也可以单独确认框架启动。
task mshr_base_test::run_sequence();
    repeat (10) @(negedge vif.clk);
    check_counts(0, 0, 0);
endtask

// 确认上游是active配置，再允许子test启动sequence。
function void mshr_base_test::require_active_agent();
    // 【防御性检查】有激励的test需要active agent及sequencer，避免在passive配置下启动。
    if (env.agent.sequencer == null) begin
        `fatal("Stimulus requires an active MSHR agent", "MSHR_NO_SEQUENCER")
    end
endfunction

// 上游sequence结束后，等待模型、实际Entry/Slot记录和内存代理全部排空；由全局watchdog保护。
task mshr_base_test::wait_for_drain();
    repeat (2) @(negedge vif.clk);
    while (!env.is_idle()) begin
        @(negedge vif.clk);
    end
    // 多观察两个周期，发现排空后重复发送/fill/replay等伪事件。
    repeat (2) @(negedge vif.clk);
endtask

// 共享精确计数检查，失败时同时报告观察值和要求值，子test不用重复拼条件。
function void mshr_base_test::check_count(string name, int actual, int expected);
    if ($isunknown({actual, expected}) || expected < 0 || actual != expected) begin
        `error($sformatf("%s: observed=%0d expected=%0d", name, actual, expected), "MSHR_TEST_COUNT")
    end
endfunction

// 检查完整生命周期的分配、读发送/响应、fill、replay和释放计数。
function void mshr_base_test::check_counts(int allocations, int merges, int replays);
    check_count("alloc", env.scoreboard.alloc_count, allocations);
    check_count("merge", env.scoreboard.merge_count, merges);
    check_count("read request", env.scoreboard.send_count, allocations);
    check_count("read response", env.scoreboard.response_count, allocations);
    check_count("fill", env.scoreboard.fill_count, allocations);
    check_count("entry release", env.scoreboard.release_count, allocations);
    check_count("replay", env.scoreboard.replay_count, replays);
endfunction

function void mshr_base_test::report_phase(uvm_phase phase);
    uvm_report_server server;
    super.report_phase(phase);
    server = uvm_report_server::get_server();
    if (server.get_severity_count(UVM_ERROR) == 0 && server.get_severity_count(UVM_FATAL) == 0) begin
        `info("MSHR framework checks passed", "MSHR_TEST_PASS")
    end else begin
        `info("MSHR framework checks failed", "MSHR_TEST_FAIL")
    end
endfunction
