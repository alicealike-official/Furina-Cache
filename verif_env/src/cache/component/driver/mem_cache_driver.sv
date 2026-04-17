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
    tr.mem_req      <= cache_vif.mem_req;
    tr.mem_wr_en    <= cache_vif.mem_wr_en;
    tr.mem_addr     <= cache_vif.mem_addr;
    for (int i = 0; i < `WORDS_PER_BLOCK; i++) begin
        // 计算向量中的起始位位置
        int start_bit = i * `DATA_WIDTH;
        tr.mem_wdata[i] <= cache_vif.mem_wdata[start_bit +: `DATA_WIDTH];
    end
    
    wait(tr.mem_resp);
        
    cache_vif.mem_resp = tr.mem_resp;
    for (int i = 0; i < `WORDS_PER_BLOCK; i++) begin
        // 计算向量中的起始位位置
        int start_bit = i * `DATA_WIDTH;
        cache_vif.mem_rdata[start_bit +: `DATA_WIDTH] <= tr.mem_rdata[i];
    end
    @(posedge cache_vif.clk); 
endtask