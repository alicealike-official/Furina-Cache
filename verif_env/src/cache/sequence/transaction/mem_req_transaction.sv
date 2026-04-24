class mem_req_transaction extends uvm_sequence_item;
    bit                            mem_req_valid;     
    bit                            mem_wr_en;  
    bit [`DATA_ADDR_BUS-1 : 0]     mem_addr;     
    bit [`DATA_WIDTH-1 : 0]        mem_wdata[`WORDS_PER_BLOCK];
    bit                            mem_resp_ready;

    int trans_id;
    static int next_id = 0;
    `uvm_object_utils(mem_req_transaction)

    function new(string name = "mem_req_transaction");
        super.new();
        trans_id = next_id++;
    endfunction
    extern virtual function string convert2string();
endclass

function string mem_req_transaction::convert2string();
    return $sformatf("MEM[%0d]: %s addr=%0h", 
                    trans_id, mem_wr_en?"WR":"RD",
                    mem_addr);
endfunction