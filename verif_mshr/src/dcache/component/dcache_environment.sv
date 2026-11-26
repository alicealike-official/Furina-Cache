class dcache_environment extends uvm_env;
    clk_rst_agent clk_agent;
    dcache_agent agent;
    dcache_activity_monitor activity;
    dcache_probe_monitor probe_monitor;
    dcache_perf_monitor perf_monitor;
    virtual dcache_probe_interface probe_vif;
    virtual mshr_interface mshr_vif;
    virtual wbb_interface wbb_vif;
    dcache_ip_checks ip_checks;
    dcache_cachemem_checks cachemem_checks;
    dcache_memory_agent memory_agent;
    dcache_predictor predictor;
    dcache_scoreboard scoreboard;
    dcache_sink_driver sink_driver;
    // 原C++ SparseMemory的SV封装，与CacheTop参考模型状态相互独立。
    dcache_memory_store memory;
    dcache_config cfg;
    clk_rst_config clock_cfg;
    `uvm_component_utils(dcache_environment)
    function new(string name = "dcache_environment", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】时钟配置必须由TB->test->env传递，不创建默认时钟对象。
        if (!uvm_config_db #(dcache_config)::get(this, "", "dcache_config", cfg) ||
            !uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clock_cfg)) begin
            `fatal("Environment configuration missing", "DCACHE_CONFIG")
        end
        // 【防御性检查】每个顶层case都接入真实内部IP接口；缺失时不能静默关闭局部检查。
        if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", mshr_vif) ||
            !uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", wbb_vif)) begin
            `fatal("Passive IP binding missing", "DCACHE_IP_CONFIG")
        end
        uvm_config_db #(virtual mshr_interface)::set(this, "*", "mshr_vif", mshr_vif);
        uvm_config_db #(virtual wbb_interface)::set(this, "*", "wbb_vif", wbb_vif);
        ip_checks = dcache_ip_checks::type_id::create("ip_checks", this);
        memory = dcache_memory_store::type_id::create("memory");
        memory.initialize();
        uvm_config_db #(dcache_config)::set(this, "*", "dcache_config", cfg);
        uvm_config_db #(dcache_memory_store)::set(this, "*", "memory", memory);
        uvm_config_db #(clk_rst_config)::set(this, "clk_agent", "clk_rst_config", clock_cfg);
        clk_agent = clk_rst_agent::type_id::create("clk_agent", this);
        if (cfg.enable_probes) begin
            // 【防御性检查】探针case必须取得真实bind接口，不能静默降级成外部IO测试。
            if (!uvm_config_db #(virtual dcache_probe_interface)::get(this, "", "dcache_probe_vif", probe_vif)) begin
                `fatal("Probe bind missing", "DCACHE_PROBE_CONFIG")
            end
            uvm_config_db #(virtual dcache_probe_interface)::set(this, "*", "dcache_probe_vif", probe_vif);
            cachemem_checks = dcache_cachemem_checks::type_id::create("cachemem_checks", this);
            probe_monitor = dcache_probe_monitor::type_id::create("probe_monitor", this);
        end
        if (cfg.enable_perf) begin
            // 【防御性检查】性能资源和路径计数要求已接入的真实只读接口。
            if (!cfg.enable_probes) begin
                `fatal("Performance measurement requires existing probes", "DCACHE_PERF_CONFIG")
            end
            perf_monitor = dcache_perf_monitor::type_id::create("perf_monitor", this);
        end
        activity = dcache_activity_monitor::type_id::create("activity", this);
        agent = dcache_agent::type_id::create("agent", this);
        memory_agent = dcache_memory_agent::type_id::create("memory_agent", this);
        sink_driver = dcache_sink_driver::type_id::create("sink_driver", this);
        predictor = dcache_predictor::type_id::create("predictor", this);
        scoreboard = dcache_scoreboard::type_id::create("scoreboard", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.monitor_port.connect(memory_agent.driver.analysis_export);
        agent.monitor.monitor_port.connect(predictor.analysis_export);
        predictor.compare_port.connect(scoreboard.analysis_export);
        agent.monitor.monitor_port.connect(activity.analysis_export);
        if (perf_monitor != null) agent.monitor.monitor_port.connect(perf_monitor.analysis_export);
        if (agent.sequencer != null) begin
            agent.sequencer.perf_monitor = perf_monitor;
            agent.sequencer.probe_monitor = probe_monitor;
            agent.sequencer.observations = activity;
            agent.sequencer.cfg = cfg;
            agent.sequencer.memory = memory;
        end
    endfunction
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        // 各monitor同频采样，两个独立IP检查链应各收到一份完整逐拍快照。
        if (ip_checks.mshr.scoreboard.checked_cycles != scoreboard.cycles ||
            ip_checks.wbb.scoreboard.checked_cycles != scoreboard.cycles) begin
            `error("Top/IP sample cycle counts differ", "DCACHE_IP_SAMPLING")
        end
    endfunction
    // 同时检查CPU与后端已接受的事务，保留脏行属于正常Cache状态。
    function bit is_idle();
        return scoreboard.is_idle() && memory_agent.driver.is_idle();
    endfunction
    function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        memory.close();
    endfunction
endclass
