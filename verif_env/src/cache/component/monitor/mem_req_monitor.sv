class mem_req_monitor extends uvm_monitor;
    virtual cache_interface cache_vif;
    uvm_analysis_port #(mem_req_transaction) mem_req_mon_port;
    
    `uvm_component_utils(mem_req_monitor)
    
    function new(string name = "mem_req_monitor",
                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end

        mem_req_mon_port = new("mem_req_mon_port", this);
    endfunction
    

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task collect_transaction();

endclass

function void mem_req_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db #(virtual cache_interface)::get(this, "", "cache_vif", cache_vif))
        `fatal("cache_interface not found")
endfunction
    
task mem_req_monitor::run_phase(uvm_phase phase);
    wait(cache_vif.rst_n);
    repeat(3)@(posedge cache_vif.clk);
    fork
        collect_transaction();
    join
endtask
    
task mem_req_monitor::collect_transaction();
    

    forever begin
        mem_req_transaction tr;
        tr = new();
        // do begin
        //     @(posedge cache_vif.clk);
        // end while (!(cache_vif.mem_req_valid && cache_vif.mem_req_ready));

        // @(negedge cache_vif.clk);
        @(posedge cache_vif.clk iff cache_vif.mem_req_valid && cache_vif.mem_req_ready);
        
        tr.mem_wr_en = cache_vif.mem_wr_en;
        tr.mem_addr = cache_vif.mem_addr;
        // for (int idx = 0; idx < `WORDS_PER_BLOCK; idx++) begin
        //     tr.mem_wdata[idx] = cache_vif.mem_wdata[(idx+1)*`DATA_WIDTH - 1 : idx * `DATA_WIDTH];
        // end
        {>>{tr.mem_wdata}} = cache_vif.mem_wdata;
        -> cache_vif.mem_req_monitor_evt;
        mem_req_mon_port.write(tr);
    end
endtask
