class cpu_driver extends uvm_driver #(cpu_req_transaction);
    virtual cache_interface cache_vif;
    uvm_analysis_port #(cpu_req_transaction) driver_port;
    `uvm_component_utils(cpu_driver)
    
    function new(string name = "cpu_driver",
                uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        driver_port = new("driver_port", this);
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
    wait(cache_vif.rst_n);
    cache_vif.cpu_req_valid    <= 0;
    repeat(3) @(posedge cache_vif.clk);

    `ifdef DEBUG
    -> cache_vif.state_begin_to_driver;
    `endif

    forever begin
        seq_item_port.get_next_item(req);
        
        drive_transaction(req);
        seq_item_port.item_done();
    end
endtask
    
task cpu_driver::drive_transaction(cpu_req_transaction cpu_req_tr);
    // //发起请求（先拉高 valid）
    // cache_vif.cpu_valid    <= 1;
    // cache_vif.cpu_wr_en    <= cpu_req_tr.cpu_wr_en;
    // cache_vif.cpu_req_addr <= cpu_req_tr.cpu_req_addr;
    // cache_vif.cpu_wdata    <= cpu_req_tr.cpu_wdata;

    // //等待握手成功
    // do begin
    //     @(posedge cache_vif.clk);
    // end while (!(cache_vif.cpu_valid && cache_vif.cpu_ready));

    // //下一拍再拉低 valid
    // @(posedge cache_vif.clk);
    // cache_vif.cpu_valid <= 0;

    // //等 cache 完成
    // do begin
    //     @(posedge cache_vif.clk);
    // end while (!cache_vif.cpu_ready);
        // 发起请求
    -> cache_vif.state_begin_to_drive;
    driver_port.write(cpu_req_tr);
    //$display("driver valid= %0d", cpu_req_tr.cpu_req_valid);
    cache_vif.cpu_req_valid     <= cpu_req_tr.cpu_req_valid;
    cache_vif.cpu_resp_ready    <= cpu_req_tr.cpu_resp_ready;
    cache_vif.cpu_wr_en         <= cpu_req_tr.cpu_wr_en;
    cache_vif.cpu_req_addr      <= cpu_req_tr.cpu_req_addr;
    cache_vif.cpu_wdata         <= cpu_req_tr.cpu_wdata;

    // 只等 handshake
    do begin
        @(posedge cache_vif.clk);
    end while (!(cache_vif.cpu_resp_valid && cpu_req_tr.cpu_resp_ready));

    // 下一拍撤 valid
    // @(posedge cache_vif.clk);
    // cache_vif.cpu_valid <= 0;
endtask
