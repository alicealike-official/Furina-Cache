class clk_rst_config extends uvm_object;
        real clock_period = 20;     //50MHz
        real initial_reset_cycles = 1;

        uvm_active_passive_enum is_active = UVM_ACTIVE;
        `uvm_object_utils(clk_rst_config)

        function new(
                string name = "clk_rst_config"
        );
                super.new(name);
        endfunction
endclass
