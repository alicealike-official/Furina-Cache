class cpu_driver extends uvm_driver #(cpu_req_transaction);
    virtual cache_interface cache_vif;
    
    `uvm_component_utils(cpu_driver)
    
    function new(string name = "cpu_driver",
                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction
    

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task drive_transaction(cpu_req_transaction cpu_req_tr);

endclass

function void cpu_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task cpu_driver::run_phase(uvm_phase phase);
    forever begin
        seq_item_port.get_next_item(req);
        drive_transaction(req);
        seq_item_port.item_done();
    end
endtask
    
task cpu_driver::drive_transaction(cpu_req_transaction cpu_req_tr);
    wait(cache_vif.rst_n);
    $display(cpu_req_tr.convert2string());
    cache_vif.cpu_req <= cpu_req_tr.cpu_req;
    cache_vif.cpu_wr_en <= cpu_req_tr.cpu_wr_en;
    cache_vif.cpu_req_addr <= cpu_req_tr.cpu_req_addr;
    cache_vif.cpu_wdata <= cpu_req_tr.cpu_wdata;

    wait(cache_vif.ready);  
    // tr.cache_rdata = cache_vif.cache_rdata;
    // tr.ready = cache_vif.ready; 
    @(posedge cache_vif.clk);
endtask
