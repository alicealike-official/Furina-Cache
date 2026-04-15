class cpu_cache_transaction extends cache_base_transaction;
    //请求
    rand  bit                       cpu_req;    
    rand  bit                       cpu_wr_en;    
    rand  bit [DataAddrBus-1 : 0]   cpu_req_addr;
    rand  bit [DataWidth-1 : 0]     cpu_wdata;

    //响应
    rand  bit [DataWidth-1 : 0]     cache_rdata;    
    rand  bit                       ready;          
    `uvm_object_utils(cpu_cache_transaction)

    constraint addr_align {
        cpu_req_addr[1:0] == 2'b00;
    }

    function new(string name = "cpu_cache_transaction");
        super.new();
    endfunction

    extern virtual function string convert2string();
endclass

function string cpu_cache_transaction::convert2string();
    return $sformatf("CPU[%0d]: %s addr=%0h, data=%0h", 
                    trans_id, cpu_wr_en?"WR":"RD", cpu_req_addr, 
                    cpu_wr_en?cpu_wdata:cache_rdata);
endfunction