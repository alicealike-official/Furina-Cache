// cache_environment.sv
import uvm_pkg::*;
import cache_pkg::*;
import clk_rst_pkg::*;
`include "uvm_macros.svh"
class cache_environment extends uvm_env;
    cpu_agent cpu_agt;
//    mem_cache_agent mem_cache_agt;

    clk_rst_agent clk_rst_agt;
    clk_rst_config clk_rst_cfg;
    //cache_virtual_sequencer cache_vsqr;
    cpu_stimulus_scoreboard cpu_stimulus_sbd;
    d_cache_model d_cache_mdl;

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
    cpu_agt = cpu_agent::type_id::create("cpu_agt", this);
//    mem_cache_agt = mem_cache_agent::type_id::create("mem_cache_agt", this);
    clk_rst_agt = clk_rst_agent::type_id::create("clk_rst_agt", this);

    clk_rst_cfg = clk_rst_config::type_id::create("clk_rst_config");
    cpu_stimulus_sbd = cpu_stimulus_scoreboard::type_id::create("cpu_stimulus_scoreboad", this);
    d_cache_mdl = d_cache_model::type_id::create("d_cache_model", this);
    clk_rst_cfg.clock_period = 10;
    clk_rst_cfg.initial_reset_cycles = 1;
    // 通过 config_db 传递给 driver
    uvm_config_db#(clk_rst_config)::set(this, "*", "clk_rst_config", clk_rst_cfg);
endfunction


function void cache_environment::connect_phase(uvm_phase phase);
    // 将sequencer通过config_db传递给virtual sequence
    uvm_config_db #(uvm_sequencer #(cpu_req_transaction))::set(
        null, "*", "cpu_req_sqr", cpu_agt.cpu_req_sqr);
    //uvm_config_db #(uvm_sequencer #(mem_cache_transaction))::set(
    //    null, "*", "mem_cache_sqr", mem_cache_agt.sequencer);
    
    //agent连接scoreboard
    cpu_agt.cpu_drv.driver_port.connect(cpu_stimulus_sbd.driver_export);
    cpu_agt.cpu_in_mon.cpu_in_mon_port.connect(cpu_stimulus_sbd.monitor_export);

    //agent连接ref_model
    cpu_agt.cpu_in_mon.cpu_in_mon_port.connect(d_cache_mdl.cpu_req_fifo.analysis_export);
    cpu_agt.mem_rsp_mon.mem_rsp_mon_port.connect(d_cache_mdl.mem_rsp_fifo.analysis_export);

endfunction