class mem_rsp_transaction extends uvm_sequence_item;
    bit                            mem_req_ready;
    bit                            mem_resp_valid;    
    bit [`DATA_WIDTH-1 : 0]        mem_rdata[`WORDS_PER_BLOCK];

    int trans_id;
    static int next_id = 0;
    `uvm_object_utils(mem_rsp_transaction)

    function new(string name = "mem_rsp_transaction");
        super.new();
        trans_id = next_id++;
    endfunction
    extern virtual function string convert2string();
endclass

function string mem_rsp_transaction::convert2string();
endfunction