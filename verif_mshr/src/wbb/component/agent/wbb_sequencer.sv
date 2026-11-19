class wbb_sequencer extends uvm_sequencer #(wbb_transaction);
    wbb_config cfg;
    wbb_activity_monitor observations;
    `uvm_component_utils(wbb_sequencer)

    function new(string name = "wbb_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
endclass

function void wbb_sequencer::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg) || cfg == null ||
        !uvm_config_db #(wbb_activity_monitor)::get(this, "", "observations", observations) || observations == null) begin
        `fatal("Scenario sequencer requires configuration and IO observations", "WBB_SEQUENCE_CONFIG")
    end
endfunction
