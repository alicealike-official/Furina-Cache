class cache_out_monitor extends uvm_monitor;
    virtual cache_interface cache_vif;
    uvm_analysis_port #(cache_rsp_transaction) cache_out_mon_port;
    
    `uvm_component_utils(cache_out_monitor)
    
    function new(string name = "cache_out_monitor",
                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end

        cache_out_mon_port = new("cache_out_mon_port", this);
    endfunction
    

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task collect_transaction();

endclass

function void cache_out_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task cache_out_monitor::run_phase(uvm_phase phase);
    wait(cache_vif.rst_n);
    repeat(3)@(posedge cache_vif.clk);
    fork
        collect_transaction();
    join
endtask
    
task cache_out_monitor::collect_transaction();
    

    forever begin
        cache_rsp_transaction tr;
        tr = new();
        // do begin
        //     @(posedge cache_vif.clk);
        // end while (!(cache_vif.cpu_resp_valid));
        // while(!(cache_vif.cpu_resp_valid)) begin
        //     @(posedge cache_vif.clk);
        // end
        // @(negedge cache_vif.clk);

        // tr.trans_id = tr.monitor_id++;
        // tr.cpu_req_ready    = cache_vif.cpu_req_ready;
        // tr.cache_rdata      = cache_vif.cache_rdata;
        // tr.cpu_resp_valid   = cache_vif.cpu_resp_valid;


        @(posedge cache_vif.clk iff cache_vif.cpu_resp_valid);
        -> cache_vif.cache_out_monitor_evt;
        tr.trans_id        = tr.monitor_id++;
        tr.cpu_req_ready  = cache_vif.cpu_req_ready;
        tr.cache_rdata    = cache_vif.cache_rdata;
        //$display("rdate = %0x", cache_vif.cache_rdata);
        tr.cpu_resp_valid = cache_vif.cpu_resp_valid;
        cache_out_mon_port.write(tr);
    end
endtask
