// 独立MSHR检查实例：输入来自真实内部接口，C++对象由原mshr_predictor单独创建。
class dcache_mshr_checks extends uvm_env;
    mshr_pkg::mshr_agent agent;
    mshr_pkg::mshr_predictor predictor;
    mshr_pkg::mshr_scoreboard scoreboard;
    `uvm_component_utils(dcache_mshr_checks)
    function new(string name = "dcache_mshr_checks", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        mshr_pkg::mshr_config cfg;
        dcache_config top_cfg;
        super.build_phase(phase);
        cfg = mshr_pkg::mshr_config::type_id::create("cfg");
        cfg.is_active = UVM_PASSIVE;
        // 【防御性检查】系统取消约定来自顶层配置，不由被动IP环境自行选择。
        if (!uvm_config_db #(dcache_config)::get(this, "", "dcache_config", top_cfg)) begin
            `fatal("Top reset policy missing", "DCACHE_IP_CONFIG")
        end
        cfg.allow_reset_cancellation = top_cfg.allow_reset_cancellation;
        uvm_config_db #(mshr_pkg::mshr_config)::set(this, "*", "mshr_config", cfg);
        agent = mshr_pkg::mshr_agent::type_id::create("agent", this);
        predictor = mshr_pkg::mshr_predictor::type_id::create("predictor", this);
        scoreboard = mshr_pkg::mshr_scoreboard::type_id::create("scoreboard", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.monitor_port.connect(predictor.monitor_export);
        predictor.compare_port.connect(scoreboard.compare_export);
    endfunction
endclass
