class cache_rsp_transaction extends uvm_sequence_item;
    //响应
    rand  bit [`DATA_WIDTH-1 : 0]     cache_rdata;    
    rand  bit                         cpu_req_ready;
    rand  bit                         cpu_resp_valid;

    int trans_id;
    static int scoreboard_id = 0;
    static int monitor_id    = 0;
    `uvm_object_utils(cache_rsp_transaction)

    function new(string name = "cache_rsp_transaction");
        super.new();
    endfunction

    extern virtual function string convert2string();
endclass

function string cache_rsp_transaction::convert2string();
    string info = $sformatf("CPU_RSP[%0d], rdata=%0d", trans_id, cache_rdata);
    return info;
endfunction