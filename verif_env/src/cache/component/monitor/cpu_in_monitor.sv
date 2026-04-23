class cpu_in_monitor extends uvm_monitor;
    virtual cache_interface cache_vif;
    uvm_blocking_put_port #(cpu_req_transaction) cpu_req_port;
    
    `uvm_component_utils(cpu_in_monitor)
    
    function new(string name = "cpu_in_monitor",
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

function void cpu_in_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task cpu_in_monitor::run_phase(uvm_phase phase);
    wait(cache_vif.rst_n);
    @(posedge cache_vif.clk);
    `ifdef DEBUG
    ->cache_vif.state_begin_to_mon;
    `endif
    fork
        collect_transaction();
    join
endtask
    
task cpu_in_monitor::collect_transaction();
    cpu_req_transaction tr;

    forever begin
        
        @(negedge cache_vif.clk);
        tr = new();
        tr.trans_id = tr.monitor_id++;
        
        tr.cpu_req_valid <= cache_vif.cpu_req_valid;
        tr.cpu_wr_en <= cache_vif.cpu_wr_en;
        tr.cpu_req_addr <= cache_vif.cpu_req_addr;
        tr.cpu_wdata <= cache_vif.cpu_wdata;
        while(!cache_vif.cpu_req_ready) begin
           @(posedge cache_vif.clk);
        end
        @(posedge cache_vif.clk);
        $display({"MONITOR: ",tr.convert2string()});

        //cpu_req_port.write(tr);
    end
endtask
