/*=============================================================================
#
# Author: Alicealike
#
# Email: alicealike@foxmail.com
#
# Last modified:	2025-10-20 00:15
#
# Filename:		clk_rst_driver.sv
#
# Description: 
#
# Functional Verification: 
#
# Timing Verification: 
#
=============================================================================*/
class clk_rst_driver extends uvm_driver#(uvm_sequence_item);
        virtual clk_rst_interface clk_rst_vif;
        clk_rst_config clk_rst_cfg;

        bit clock_enable = 1;
        realtime t_high;
        realtime t_low;
        realtime reset_time;

        `uvm_component_utils_begin(clk_rst_driver)
        `uvm_component_utils_end

        function new(
                string name = "clk_rst_driver",
                uvm_component parent = null
        );
                super.new(name, parent);
                if (parent == null) begin
                        `uvm_fatal("DRIVER", "This component' parent can not be null!!")
                end
        endfunction

        extern function void build_phase(uvm_phase phase);
        extern function void start_of_simulation_phase(uvm_phase phase);
        extern task run_phase(uvm_phase phase);

        extern task back_ground_clk();
        extern task set_reset();
        extern function void update_timing();
        extern function void clock_validity_check();
        extern function void stop_clock();
endclass

function void clk_rst_driver::build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual clk_rst_interface)::get(this,"","clk_rst_vif",clk_rst_vif)) begin
                `uvm_fatal("NOVIF", "virtual interface not found")
        end

        if (!uvm_config_db#(clk_rst_config)::get(this,"","clk_rst_cfg",clk_rst_cfg)) begin
                `uvm_fatal("NOCFG","clock config not found")
        end
endfunction

function void clk_rst_driver::start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        update_timing();
        clock_validity_check();
endfunction

task clk_rst_driver::run_phase(uvm_phase phase);
        phase.raise_objection(this, "clk running");
        fork
                back_ground_clk();
                set_reset();
        join

        phase.drop_objection(this);
endtask

task clk_rst_driver::back_ground_clk();
        clk_rst_vif.clk_drv <= 0;
        while(clock_enable) begin
                #(this.t_high);
                clk_rst_vif.clk_drv <= 1;
                #(this.t_low);
                clk_rst_vif.clk_drv <= 0;
        end
endtask

task clk_rst_driver::set_reset();
        clk_rst_vif.rst_n_drv <= 0;
        #(this.reset_time);
        clk_rst_vif.rst_n_drv <=1;
endtask

function void clk_rst_driver::update_timing();
        this.t_high = clk_rst_cfg.clock_period/2;
        this.t_low = clk_rst_cfg.clock_period/2;
        this.reset_time = clk_rst_cfg.clock_period * clk_rst_cfg.initial_reset_cycles;
endfunction

function void clk_rst_driver::clock_validity_check();
        if ((this.t_high == 0) || (this.t_low == 0)) begin
                `uvm_fatal("CLOCK VALID", "Clock period can not be zero!!")
        end

        if (this.reset_time == 0) begin
                `uvm_fatal("CLOCK VALID", "Reset time can not be zero!!")
        end
endfunction

function void clk_rst_driver::stop_clock();
clock_enable = 0;
endfunction