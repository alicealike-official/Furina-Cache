class clk_rst_driver extends uvm_driver #(uvm_sequence_item);
    virtual clk_rst_interface vif;
    clk_rst_config cfg;
    `uvm_component_utils(clk_rst_driver)

    function new(string name = "clk_rst_driver",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

function void clk_rst_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual clk_rst_interface)::get(this, "", "clk_rst_vif", vif)) begin
        `fatal("clk_rst_interface not found")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", cfg) || cfg == null) begin
        `fatal("Parent clock agent must provide a non-null clk_rst_config", "CLK_CONFIG")
    end
    // 【防御性检查】仿真时钟参数必须有效，防止错误配置使测试无法推进。
    if (cfg.clock_period <= 0 || cfg.initial_reset_cycles == 0) begin
        `fatal("Clock period and reset cycles must be positive")
    end
endfunction

task clk_rst_driver::run_phase(uvm_phase phase);
    vif.clk_drv <= 0;
    vif.rst_n_drv <= 0;
    fork
        forever begin
            #(cfg.clock_period / 2);
            vif.clk_drv <= ~vif.clk_drv;
        end
        begin
            repeat (cfg.initial_reset_cycles) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.rst_n_drv <= 1;
        end
    join
endtask
