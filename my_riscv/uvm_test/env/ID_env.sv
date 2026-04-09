import uvm_pkg::*;
import ID_pkg::*;
import clk_rst_pkg::*;
`include "uvm_macros.svh"
class ID_env extends uvm_env;
    ID_agent ID_agt;
    clk_rst_agent clk_rst_agt;
    ID_ref_model ref_mdl;
    ID_scoreboard sbd;

    
    `uvm_component_utils(ID_env)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        clk_rst_agt = clk_rst_agent::type_id::create("clk_rst_agt", this);
        ID_agt = ID_agent::type_id::create("ID_agt", this);
        ref_mdl = ID_ref_model::type_id::create("ref_mdl", this);
        sbd = ID_scoreboard::type_id::create("sbd", this);
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        ID_agt.mon.ap_instr.connect(sbd.instr_analysis_imp);

    endfunction
endclass
