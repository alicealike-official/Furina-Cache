class ID_driver extends uvm_driver #(instr_transaction);
    virtual ID_interface ID_vif;
    
    `uvm_component_utils(ID_driver)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        if(!uvm_config_db#(virtual ID_interface)::get(this, "", "ID_vif", ID_vif))
            `uvm_fatal("DRV", "Failed to get interface")
    endfunction
    
    task run_phase(uvm_phase phase);
        instr_transaction req;
        forever begin
            seq_item_port.get_next_item(req);
            ID_vif.instruction <= req.instruction;
            //$display("req = %d", req.instruction);
            @(posedge ID_vif.clock);
            seq_item_port.item_done();
        end
    endtask
endclass
