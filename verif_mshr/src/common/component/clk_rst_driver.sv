class clk_rst_driver extends uvm_driver #(uvm_sequence_item);
    virtual clk_rst_interface vif;
    clk_rst_config cfg;
    bit clock_running = 1;
    int reset_requests;
    longint unsigned rising_edges;
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
    extern task assert_reset(bit stop_clock = 0);
    extern task release_reset(bit before_falling_edge = 0);
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
            if (clock_running) begin
                if (!vif.clk_drv) rising_edges++;
                vif.clk_drv <= ~vif.clk_drv;
            end
        end
        begin
            real first_edge;
            real measured_period;
            @(posedge vif.clk);
            first_edge = $realtime;
            @(posedge vif.clk);
            measured_period = $realtime - first_edge;
            // 【防御性检查】1ps只作本package仿真精度容差，不是硬编码激励延迟。
            if (measured_period < cfg.clock_period - 0.001 || measured_period > cfg.clock_period + 0.001) begin
                `fatal("Measured clock period differs from top clock config", "CLK_PERIOD")
            end
            `info($sformatf("configured_ns=%0.6f measured_ns=%0.6f", cfg.clock_period,
                measured_period), "CLK_RESET_CONFIG")
        end
        begin
            repeat (cfg.initial_reset_cycles) @(posedge vif.clk);
            @(negedge vif.clk);
            vif.rst_n_drv <= 1;
        end
    join
endtask

// 由唯一时钟复位driver在非有效沿拉低复位；可停在低电平，返回时仍未发生下一有效沿。
task clk_rst_driver::assert_reset(bit stop_clock);
    // 【防御性检查】运行期复位不能与启动复位或另一请求重叠。
    if (vif.rst_n !== 1'b1) begin
        `fatal("Reset is already active", "CLK_RESET_REQUEST")
    end
    @(negedge vif.clk);
    if (stop_clock) clock_running = 0;
    #(cfg.clock_period / 4.0);
    vif.rst_n_drv <= 0;
    reset_requests++;
    #(cfg.clock_period / 8.0);
endtask

// 先恢复时钟并保持复位两个有效沿；默认下降沿释放，边界测试可提前四分之一周期释放。
task clk_rst_driver::release_reset(bit before_falling_edge);
    // 【防御性检查】只有已经断言的复位才能被释放。
    if (vif.rst_n !== 1'b0) begin
        `fatal("Reset must be active before release", "CLK_RESET_REQUEST")
    end
    clock_running = 1;
    repeat (2) @(posedge vif.clk);
    if (before_falling_edge) begin
        #(cfg.clock_period / 4.0);
    end else begin
        @(negedge vif.clk);
    end
    vif.rst_n_drv <= 1;
    #(cfg.clock_period / 8.0);
endtask
