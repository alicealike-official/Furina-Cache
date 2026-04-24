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
    extern virtual function bit compare(uvm_object rhs, uvm_comparer = null);
endclass

function string mem_req_transaction::convert2string();
    return $sformatf("MEM[%0d]: %s addr=%0h", 
                    trans_id, mem_wr_en?"WR":"RD",
                    mem_addr);
endfunction

function bit mem_req_transaction::compare(uvm_object rhs, uvm_comparer = null);
        mem_req_transaction tr;
        bit match = 1'b1;

        // 类型检查
        if (!$cast(tr, rhs)) begin
            `error("Type mismatch")
            return 0;
        end

        if (mem_wr_en != tr.mem_wr_en) begin
            match = 0;
            `info_med($sformatf("wr_en mismatch: %0h vs %0h",mem_wr_en, tr.mem_wr_en))
        end
        
        if (mem_addr != tr.mem_addr) begin
            match = 0;
            `info_med($sformatf("addr mismatch: %0h vs %0h",mem_addr, tr.mem_addr))
        end

        if (mem_wdata != tr.mem_wdata) begin
            match = 0;
            `info_med($sformatf("write data mismatch"))
        end
        return match;
endfunction