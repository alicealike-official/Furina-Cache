class mshr_sink_driver extends uvm_component;
    virtual mshr_interface vif;
    mshr_config cfg;

    `uvm_component_utils(mshr_sink_driver)

    function new(string name = "mshr_sink_driver",
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

function void mshr_sink_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", vif) || vif == null) begin
        `fatal("mshr_interface not found", "MSHR_CONFIG")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null) begin
        `fatal("Parent environment must provide a non-null mshr_config", "MSHR_CONFIG")
    end
endfunction

task mshr_sink_driver::run_phase(uvm_phase phase);
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

// 复位期间禁止接受 fill 和 replay；本组件只驱动接收控制，不修改数据或 DUT 状态。
task mshr_sink_driver::drive_idle();
    vif.fillReady <= 0;
    vif.replay_ready <= 0;
endtask

// 在下降沿应用当前接收开关，分别控制下一上升沿的 fill 和 replay 接受。
task mshr_sink_driver::drive_acceptance();
    // 【防御性检查】接收端的运行配置必须已知，避免TB把X/Z驱动到ready。
    if ($isunknown({cfg.fill_enable, cfg.replay_enable})) begin
        `fatal("Fill/replay acceptance configuration contains X/Z", "MSHR_CONFIG")
    end
    vif.fillReady <= cfg.fill_enable;
    vif.replay_ready <= cfg.replay_enable;
endtask
