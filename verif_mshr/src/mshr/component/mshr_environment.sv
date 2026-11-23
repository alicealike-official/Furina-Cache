class mshr_environment extends uvm_env;
    clk_rst_agent clk_agent;
    clk_rst_config clk_cfg;
    mshr_config cfg;
    mshr_agent agent;
    mshr_memory_agent memory_agent;
    mshr_sink_driver sink_driver;
    // C++ MSHR的SV预测组件，经mshr_ref_* DPI访问RefModel/Cache/MSHR.hpp。
    mshr_predictor predictor;
    mshr_scoreboard scoreboard;
    // C++ SparseMemory的SV封装，经mshr_mem_* DPI访问RefModel/MEM/SparseMemory.hpp。
    mshr_memory_store memory;

    `uvm_component_utils(mshr_environment)

    function new(string name = "mshr_environment", uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent cannot be null")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual function void final_phase(uvm_phase phase);
    extern function bit is_idle();
endclass

function void mshr_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null) begin
        `fatal("Test must provide mshr_config", "MSHR_CONFIG")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clk_cfg) || clk_cfg == null) begin
        `fatal("Parent test must provide the TB clock config", "CLK_CONFIG")
    end
    memory = mshr_memory_store::type_id::create("memory");
    // initialize经DPI创建C++ SparseMemory；后端代理只读取其原始行，不把fill写回外部MEM。
    memory.initialize(cfg.mem_page_size);
    uvm_config_db #(mshr_memory_store)::set(this, "*", "memory", memory);
    uvm_config_db #(mshr_config)::set(this, "*", "mshr_config", cfg);
    uvm_config_db #(clk_rst_config)::set(this, "clk_agent", "clk_rst_config", clk_cfg);
    clk_agent = clk_rst_agent::type_id::create("clk_agent", this);
    agent = mshr_agent::type_id::create("agent", this);
    memory_agent = mshr_memory_agent::type_id::create("memory_agent", this);
    sink_driver = mshr_sink_driver::type_id::create("sink_driver", this);
    predictor = mshr_predictor::type_id::create("predictor", this);
    scoreboard = mshr_scoreboard::type_id::create("scoreboard", this);
endfunction

function void mshr_environment::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // 两个消费者接收同一份沿前快照，各自维护内存队列和C++模型状态。
    agent.monitor.monitor_port.connect(memory_agent.driver.monitor_export);
    agent.monitor.monitor_port.connect(predictor.monitor_export);
    predictor.compare_port.connect(scoreboard.compare_export);
endfunction

// 停止上游提交后，检查C++模型、内存读队列及实际IO事务记录是否全部排空。
function bit mshr_environment::is_idle();
    // predictor.is_empty内部调用mshr_ref_empty DPI；另外两项是SV接口历史检查。
    return predictor.is_empty() && memory_agent.driver.is_idle() && scoreboard.is_idle();
endfunction

function void mshr_environment::final_phase(uvm_phase phase);
    super.final_phase(phase);
    // close经mshr_mem_destroy DPI释放C++稀疏内存及其页面。
    memory.close();
endfunction
