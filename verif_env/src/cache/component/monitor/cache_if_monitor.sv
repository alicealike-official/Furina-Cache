class cache_if_monitor extends uvm_monitor#(cpu_cache_transaction);
    virtual cache_interface cache_vif;
    uvm_analysis_port #(cpu_cache_transaction) ap;
    
    `uvm_component_utils(cache_if_monitor)
    
    function new(string name = "cache_if_monitor",
                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction
    

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task collect_transaction();

endclass

function void cache_if_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task cache_if_monitor::run_phase(uvm_phase phase);
    fork
        collect_transaction();
    join_none
endtask
    
task cache_if_monitor::collect_transaction();
    cpu_cache_transaction tr;

    forever begin
        wait(cache_vif.rst_n);
        tr.cpu_req <= cache_vif.cpu_req;
        tr.cpu_wr_en <= cache_vif.cpu_wr_en;
        tr.cpu_req_addr <= cache_vif.cpu_req_addr;
        tr.cpu_wdata <= cache_vif.cpu_wdata;

        wait(cache_vif.ready);  
        tr.cache_rdata = cache_vif.cache_rdata;
        tr.ready = cache_vif.ready; 
        @(posedge cache_vif.clk);
    end
endtask

endclass