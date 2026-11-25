class dcache_sink_driver extends uvm_component;
    virtual dcache_interface vif;
    dcache_config cfg;
    int read_blocked_cycles;
    int write_blocked_cycles;

    `uvm_component_utils(dcache_sink_driver)

    function new(string name = "dcache_sink_driver",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task drive_idle();
    extern task drive_acceptance();

endclass

function void dcache_sink_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual dcache_interface)::get(this, "", "dcache_vif", vif) || vif == null) begin
        `fatal("dcache_interface not found", "MSHR_CONFIG")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(dcache_config)::get(this, "", "dcache_config", cfg) || cfg == null) begin
        `fatal("Parent environment must provide a non-null dcache_config", "MSHR_CONFIG")
    end
endfunction

task dcache_sink_driver::run_phase(uvm_phase phase);
    drive_idle();
    forever begin
        @(negedge vif.clk or negedge vif.rst_n);
        if (vif.rst_n !== 1'b1) begin
            drive_idle();
        end else begin
            drive_acceptance();
        end
    end
endtask

// 复位期间禁止接受 CPU读写响应；本组件只驱动接收控制，不修改数据或 DUT 状态。
task dcache_sink_driver::drive_idle();
    vif.cpuReadResp_ready <= 0;
    vif.cpuWriteResp_ready <= 0;
endtask

// 在下降沿应用当前接收开关，分别控制下一上升沿的 CPU读写响应 接受。
task dcache_sink_driver::drive_acceptance();
    bit read_ready;
    bit write_ready;
    // 【防御性检查】接收端的运行配置必须已知，避免TB把X/Z驱动到ready。
    if ($isunknown({cfg.cpu_read_ready, cfg.cpu_write_ready})) begin
        `fatal("Fill/replay acceptance configuration contains X/Z", "MSHR_CONFIG")
    end
    // 【防御性检查】随机接收概率与最大阻塞拍数必须有效。
    if (cfg.cpu_ready_percent < 1 || cfg.cpu_ready_percent > 100 || cfg.cpu_max_stall_cycles < 1) begin
        `fatal("Invalid CPU sink random settings", "DCACHE_CONFIG")
    end
    read_ready = !cfg.random_cpu_ready || read_blocked_cycles >= cfg.cpu_max_stall_cycles || $urandom_range(99,0) < cfg.cpu_ready_percent;
    write_ready = !cfg.random_cpu_ready || write_blocked_cycles >= cfg.cpu_max_stall_cycles || $urandom_range(99,0) < cfg.cpu_ready_percent;
    read_blocked_cycles = read_ready ? 0 : read_blocked_cycles+1;
    write_blocked_cycles = write_ready ? 0 : write_blocked_cycles+1;
    vif.cpuReadResp_ready <= cfg.cpu_read_ready && read_ready;
    vif.cpuWriteResp_ready <= cfg.cpu_write_ready && write_ready;
endtask
