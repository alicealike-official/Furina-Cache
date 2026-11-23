class mshr_sequencer extends uvm_sequencer #(mshr_transaction);
    mshr_config cfg;

    `uvm_component_utils(mshr_sequencer)

    function new(string name = "mshr_sequencer",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
endclass

function void mshr_sequencer::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null) begin
        `fatal("Parent agent must provide mshr_config", "MSHR_CONFIG")
    end
endfunction
