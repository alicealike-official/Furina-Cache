class wbb_environment extends uvm_env;
    clk_rst_agent clk_agent;
    clk_rst_config clk_cfg;
    wbb_config cfg;
    wbb_agent agent;
    wbb_scoreboard scoreboard;
    wbb_activity_monitor activity;
    // C++ WBB 参考模型的 SV 适配组件，通过 DPI 调用 RefModel/Cache/WriteBackBuffer.hpp。
    wbb_predictor predictor;
    wbb_memory_agent memory_agent;
    // C++ 稀疏内存的 SV 封装句柄，通过 DPI 访问独立的实际/期望内存实例。
    // 存储实现见 RefModel/MEM/SparseMemory.hpp，SV 封装见 model/wbb_memory_store.sv。
    wbb_memory_store memory;

    `uvm_component_utils(wbb_environment)

    function new(string name = "wbb_environment",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual function void final_phase(uvm_phase phase);
    extern function bit is_idle();
endclass

function void wbb_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg)) begin
        cfg = wbb_config::type_id::create("cfg");
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clk_cfg) || clk_cfg == null) begin
        `fatal("Parent test must provide a non-null clk_rst_config", "CLK_CONFIG")
    end
    // 【防御性检查】检查页大小、响应延迟、容量及watchdog，避免环境配置错误。
    if (cfg.mem_page_size == 0 || (cfg.mem_page_size & (cfg.mem_page_size - 1)) != 0 ||
        cfg.mem_write_latency_cycles == 0 || cfg.mem_max_pending == 0 || cfg.timeout_cycles == 0) begin
        `fatal("Invalid memory page size, latency, capacity or watchdog")
    end
    memory = wbb_memory_store::type_id::create("memory");
    // initialize() 定义于 model/wbb_memory_store.sv，通过 sparse_mem_create DPI
    // 创建实际/期望两份 C++ SparseMemory；下面传递的是持有这两个句柄的 SV 对象。
    memory.initialize(cfg.mem_page_size);
    uvm_config_db #(wbb_memory_store)::set(this, "*", "memory", memory);
    uvm_config_db #(wbb_config)::set(this, "*", "wbb_config", cfg);
    uvm_config_db #(clk_rst_config)::set(this, "clk_agent", "clk_rst_config", clk_cfg);
    activity = wbb_activity_monitor::type_id::create("activity", this);
    uvm_config_db #(wbb_activity_monitor)::set(this, "agent.sequencer", "observations", activity);
    clk_agent = clk_rst_agent::type_id::create("clk_agent", this);
    agent = wbb_agent::type_id::create("agent", this);
    scoreboard = wbb_scoreboard::type_id::create("scoreboard", this);
    predictor = wbb_predictor::type_id::create("predictor", this);
    memory_agent = wbb_memory_agent::type_id::create("memory_agent", this);
endfunction

function void wbb_environment::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Both consumers use the same pre-edge sample; they own distinct state.
    agent.monitor.monitor_port.connect(memory_agent.driver.monitor_export);
    agent.monitor.monitor_port.connect(predictor.monitor_export);
    predictor.compare_port.connect(scoreboard.compare_export);
    agent.monitor.monitor_port.connect(activity.analysis_export);
endfunction

// 停止新激励后，确认C++ WBB和SV内存响应队列均已排空。
function bit wbb_environment::is_idle();
    // predictor.is_empty() 内部通过 wbb_ref_empty DPI 查询 C++ WBB 模型的槽位占用。
    // memory_agent.driver.is_idle() 检查 SV 侧待响应队列与在途 ID。
    return predictor.is_empty() && memory_agent.driver.is_idle();
endfunction

function void wbb_environment::final_phase(uvm_phase phase);
    super.final_phase(phase);
    // close() 为 SV 封装，内部调用 sparse_mem_destroy DPI 销毁两份 C++ 稀疏内存。
    memory.close();
endfunction
