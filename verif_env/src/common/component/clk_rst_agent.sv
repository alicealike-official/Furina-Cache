class clk_rst_agent extends uvm_agent;
        clk_rst_driver driver;
        clk_rst_config clk_rst_cfg;
        `uvm_component_utils(clk_rst_agent)

        function new(
                string name = "clk_rst_agent",
                uvm_component parent = null
        );
                super.new(name, parent);
                if (parent == null) begin
                        `fatal("This component' parent can not be null!!")
                end
        endfunction

        extern virtual function void build_phase(uvm_phase phase);
endclass

function void clk_rst_agent::build_phase(uvm_phase phase);
        super.build_phase(phase);
        clk_rst_cfg = clk_rst_config::type_id::create("clk_rst_config");
        this.is_active = clk_rst_cfg.is_active;
        driver = clk_rst_driver::type_id::create("clk_rst_driver",this);
endfunction
