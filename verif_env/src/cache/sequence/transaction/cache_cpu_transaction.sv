class cache_cpu_transaction extends cache_base_transaction;
    //响应
    rand  bit [`DATA_WIDTH-1 : 0]     cache_rdata;    
    rand  bit                         ready;          
    `uvm_object_utils(cache_cpu_transaction)

    function new(string name = "cache_cpu_transaction");
        super.new();
    endfunction

    extern virtual function string convert2string();
endclass

function string cache_cpu_transaction::convert2string();
    return $sformatf("rdata=%0h", cache_rdata);
endfunction