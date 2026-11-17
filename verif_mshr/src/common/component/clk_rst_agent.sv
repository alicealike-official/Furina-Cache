class clk_rst_agent extends uvm_agent;
    clk_rst_driver driver;
    `uvm_component_utils(clk_rst_agent)

    function new(string name = "clk_rst_agent",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
endclass

function void clk_rst_agent::build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver = clk_rst_driver::type_id::create("driver", this);
endfunction
