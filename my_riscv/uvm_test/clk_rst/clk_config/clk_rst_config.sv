/*=============================================================================
#
# Author: Alicealike
#
# Email: alicealike@foxmail.com
#
# Last modified:	2025-10-20 00:14
#
# Filename:		clk_rst_config.sv
#
# Description: 
#
# Functional Verification: 
#
# Timing Verification: 
#
=============================================================================*/
class clk_rst_config extends uvm_object;
        real clock_period = 20;     //50MHz
        real initial_reset_cycles = 1;

        uvm_active_passive_enum is_active = UVM_ACTIVE;
        `uvm_object_utils_begin(clk_rst_config)
        `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
        `uvm_field_real(clock_period, UVM_ALL_ON)
        `uvm_field_real(initial_reset_cycles, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(
                string name = "clk_rst_config"
        );
                super.new(name);
        endfunction
endclass
