class mem_cache_transaction extends cache_base_transaction;
    rand bit                            mem_req;     
    rand bit                            mem_wr_en;  
    rand bit [`DATA_ADDR_BUS-1 : 0]     mem_addr;     
    rand bit [`DATA_WIDTH-1 : 0]        mem_wdata[`WORDS_PER_BLOCK];
    rand bit                            mem_resp;
    rand bit [`DATA_WIDTH-1 : 0]        mem_rdata[`WORDS_PER_BLOCK];

    `uvm_object_utils(mem_cache_transaction)

    constraint addr_align {
        mem_addr[1:0] == 2'b00;
    }
    function new(string name = "mem_cache_transaction");
        super.new();
    endfunction
    extern virtual function string convert2string();
endclass

function string mem_cache_transaction::convert2string();
    return $sformatf("MEM[%0d]: %s addr=%0h", 
                    trans_id, mem_wr_en?"WR":"RD",
                    mem_addr);
endfunction