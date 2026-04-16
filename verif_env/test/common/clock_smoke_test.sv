import clk_rst_pkg::*;

class clk_rst_smoke_test extends uvm_test;
    clk_rst_agent agent;
    clk_rst_config cfg;
    
    `uvm_component_utils(clk_rst_smoke_test)

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

    
function void clk_rst_smoke_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // 创建 agent
    agent = clk_rst_agent::type_id::create("clk_rst_agent", this);
    
    // 配置时钟参数
    cfg = clk_rst_config::type_id::create("clk_rst_config");
    cfg.clk_period = 10ns;
    cfg.clk_duty_cycle = 50;
    
    // 通过 config_db 传递给 driver
    uvm_config_db#(clk_rst_config)::set(this, "*", "clk_rst_config", cfg);
endfunction

task clk_rst_smoke_test::run_phase(uvm_phase phase);
    phase.raise_objection(this);
    
    // 发送简单时钟序列
    repeat(100) begin
        #5;  // 观察时钟波形
    end
    
    phase.drop_objection(this);
endfunction