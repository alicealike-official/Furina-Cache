class clk_rst_config extends uvm_object;
    real clock_period = 10;
    int unsigned initial_reset_cycles = 4;
    `uvm_object_utils(clk_rst_config)

    function new(string name = "clk_rst_config");
        super.new(name);
    endfunction

endclass
