class clk_rst_agent extends uvm_agent;
    clk_rst_driver driver;
    clk_rst_config cfg;
    `uvm_component_utils(clk_rst_agent)

    function new(string name = "clk_rst_agent",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
endclass

function void clk_rst_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", cfg) || cfg == null) begin
        `fatal("Parent environment must provide a non-null clk_rst_config", "CLK_CONFIG")
    end
    uvm_config_db #(clk_rst_config)::set(this, "driver", "clk_rst_config", cfg);
    driver = clk_rst_driver::type_id::create("driver", this);
endfunction
