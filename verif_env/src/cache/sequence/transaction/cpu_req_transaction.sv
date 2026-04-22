class cpu_req_transaction extends uvm_sequence_item;
    //请求
    rand  bit                           cpu_req;    
    rand  bit                           cpu_wr_en;    
    rand  bit [`DATA_ADDR_BUS-1 : 0]    cpu_req_addr;
    rand  bit [`DATA_WIDTH-1 : 0]       cpu_wdata;

    int trans_id;
    static int next_id = 0;
    `uvm_object_utils(cpu_req_transaction)

    constraint addr_align {
        cpu_req_addr[1:0] == 2'b00;
    }

    constraint wdate_mask {
        (cpu_wr_en == 0) -> (cpu_wdata == 0);
    }

    function new(string name = "cpu_req_transaction");
        super.new();
        trans_id = next_id++;
    endfunction

    extern virtual function string convert2string();
endclass

function string cpu_req_transaction::convert2string();
    string info;
    if (cpu_wr_en) begin
        info = $sformatf("CPU[%0d]: req:%s, req_addr:%0d, wdata=%0d",
                            trans_id, "WR", cpu_req_addr, cpu_wdata);
    end

    else begin
            info = $sformatf("CPU[%0d]: req:%s, req_addr:%0d",
                            trans_id, "RD", cpu_req_addr);
    end
    return info;
endfunction