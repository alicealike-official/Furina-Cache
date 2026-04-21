// cache_environment.sv
import uvm_pkg::*;
import cache_pkg::*;
import clk_rst_pkg::*;
`include "uvm_macros.svh"
class cache_environment extends uvm_env;
    cpu_cache_agent cpu_cache_agt;
//    mem_cache_agent mem_cache_agt;

    clk_rst_agent clk_rst_agt;
    clk_rst_config clk_rst_cfg;
    //cache_virtual_sequencer cache_vsqr;

    `uvm_component_utils(cache_environment)
    
    function new(string name = "cache_environment", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);

endclass


function void cache_environment::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cpu_cache_agt = cpu_cache_agent::type_id::create("cpu_agt", this);
//    mem_cache_agt = mem_cache_agent::type_id::create("mem_cache_agt", this);
    clk_rst_agt = clk_rst_agent::type_id::create("clk_rst_agt", this);

    clk_rst_cfg = clk_rst_config::type_id::create("clk_rst_config");
    clk_rst_cfg.clock_period = 10;
    clk_rst_cfg.initial_reset_cycles = 1;
    // 通过 config_db 传递给 driver
    uvm_config_db#(clk_rst_config)::set(this, "*", "clk_rst_config", clk_rst_cfg);
endfunction


function void cache_environment::connect_phase(uvm_phase phase);
    // 将sequencer通过config_db传递给virtual sequence
    uvm_config_db #(uvm_sequencer #(cpu_cache_transaction))::set(
        null, "*", "cpu_cache_sqr", cpu_cache_agt.sequencer);
    //uvm_config_db #(uvm_sequencer #(mem_cache_transaction))::set(
    //    null, "*", "mem_cache_sqr", mem_cache_agt.sequencer);
endfunction