
class instr_sequencer extends uvm_sequencer #(instr_transaction);
    `uvm_component_utils(instr_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

// class virtual_sequencer extends uvm_sequencer;
//     instr_sequencer instr_sqr;
    
//     `uvm_component_utils(virtual_sequencer)
    
//     function new(string name, uvm_component parent);
//         super.new(name, parent);
//     endfunction
// endclass
