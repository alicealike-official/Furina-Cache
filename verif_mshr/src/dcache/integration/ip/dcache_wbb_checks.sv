// 被动保存实际WBB写数据，供原wbb_scoreboard比较；不驱动内存，也不修改顶层实际MEM。
class dcache_wbb_write_observer extends uvm_subscriber #(wbb_pkg::wbb_sample);
    // 原C++ SparseMemory的SV封装，属于本地IP检查实例。
    wbb_pkg::wbb_memory_store memory;
    `uvm_component_utils(dcache_wbb_write_observer)
    function new(string name = "dcache_wbb_write_observer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 真实send握手才记录实际版本；write_actual内部经sparse_mem_* DPI访问原C++模型。
    function void write(wbb_pkg::wbb_sample t);
        if (t.rst_n && t.send_valid && t.send_ready) begin
            memory.write_actual(t.send_payload_addr, t.send_payload_wData);
        end
    endfunction
endclass

// 原WBB monitor/predictor/scoreboard直接复用；本地模型与CacheTop内的WBB对象完全独立。
class dcache_wbb_checks extends uvm_env;
    wbb_pkg::wbb_agent agent;
    wbb_pkg::wbb_predictor predictor;
    wbb_pkg::wbb_scoreboard scoreboard;
    wbb_pkg::wbb_memory_store memory;
    dcache_wbb_write_observer writes;
    `uvm_component_utils(dcache_wbb_checks)
    function new(string name = "dcache_wbb_checks", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        wbb_pkg::wbb_config cfg;
        super.build_phase(phase);
        cfg = wbb_pkg::wbb_config::type_id::create("cfg");
        cfg.is_active = UVM_PASSIVE;
        uvm_config_db #(wbb_pkg::wbb_config)::set(this, "agent", "wbb_config", cfg);
        memory = wbb_pkg::wbb_memory_store::type_id::create("memory");
        // initialize创建独立的实际/期望C++ SparseMemory对象，不共享顶层后端。
        memory.initialize(4096);
        uvm_config_db #(wbb_pkg::wbb_memory_store)::set(this, "*", "memory", memory);
        agent = wbb_pkg::wbb_agent::type_id::create("agent", this);
        predictor = wbb_pkg::wbb_predictor::type_id::create("predictor", this);
        scoreboard = wbb_pkg::wbb_scoreboard::type_id::create("scoreboard", this);
        writes = dcache_wbb_write_observer::type_id::create("writes", this);
        writes.memory = memory;
    endfunction
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.monitor_port.connect(writes.analysis_export);
        agent.monitor.monitor_port.connect(predictor.monitor_export);
        predictor.compare_port.connect(scoreboard.compare_export);
    endfunction
    function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        // close经DPI释放本地稀疏内存，独立于顶层MEM和CacheTop实例。
        memory.close();
    endfunction
endclass
