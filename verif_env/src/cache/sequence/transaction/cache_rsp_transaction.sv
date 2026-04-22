class cache_rsp_transaction extends uvm_sequence_item;
    //响应
    rand  bit [`DATA_WIDTH-1 : 0]     cache_rdata;    
    rand  bit                         ready;          
    `uvm_object_utils(cache_rsp_transaction)

    function new(string name = "cache_rsp_transaction");
        super.new();
    endfunction

    extern virtual function string convert2string();
endclass

function string cache_rsp_transaction::convert2string();
    return $sformatf("rdata=%0h", cache_rdata);
endfunction