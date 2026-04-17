class cpu_cache_driver extends uvm_driver #(cpu_cache_transaction);
    virtual cache_interface cache_vif;
    
    `uvm_component_utils(cpu_cache_driver)
    
    function new(string name = "cpu_cache_driver",
                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction
    

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task drive_transaction(cpu_cache_transaction tr);

endclass

function void cpu_cache_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task cpu_cache_driver::run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(req);
        drive_transaction(req);
        seq_item_port.item_done();
    end
endtask
    
task cpu_cache_driver::drive_transaction(cpu_cache_transaction tr);
    cache_vif.cpu_req <= tr.cpu_req;
    cache_vif.cpu_wr_en <= tr.cpu_wr_en;
    cache_vif.cpu_req_addr <= tr.cpu_req_addr;
    cache_vif.cpu_wdata <= tr.cpu_wdata;

    wait(cache_vif.ready);  
    tr.cache_rdata = cache_vif.cache_rdata;
    tr.ready = cache_vif.ready; 
    @(posedge cache_vif.clk);
endtask
