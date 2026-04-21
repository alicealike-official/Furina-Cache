class mem_cache_driver extends uvm_driver #(mem_cache_transaction);
    virtual cache_interface cache_vif;
    
    `uvm_component_utils(mem_cache_driver)
    
    function new(string name = "mem_cache_driver", 
                    uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern virtual task drive_transaction(mem_cache_transaction tr);
endclass

    
function void mem_cache_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task mem_cache_driver::run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(req);
        drive_transaction(req);
        seq_item_port.item_done();
    end
endtask
    
task mem_cache_driver::drive_transaction(mem_cache_transaction tr);
endtask