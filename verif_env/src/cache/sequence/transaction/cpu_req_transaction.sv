class cpu_req_transaction extends uvm_sequence_item;
    //请求
    rand  bit                           cpu_req_valid;
    rand  bit                           cpu_wr_en;    
    rand  bit [`DATA_ADDR_BUS-1 : 0]    cpu_req_addr;
    rand  bit [`DATA_WIDTH-1 : 0]       cpu_wdata;
    rand  bit                           cpu_resp_ready;

    int trans_id;
    static int driver_id = 0;
    static int monitor_id = 0;
    `uvm_object_utils(cpu_req_transaction)

    constraint addr_align {
        cpu_req_addr[1:0] == 2'b00;
    }

    constraint wdate_mask {
        (cpu_wr_en == 0) -> (cpu_wdata == 0);
    }

    constraint wr_en_dist {
        cpu_wr_en dist {0 := 50, 1 := 50};
    }
    
    constraint no_cpu_req {
        if (cpu_req_valid == 0) {
            cpu_wr_en == 0;
            cpu_req_addr == 0;
            cpu_wdata == 0; 
       }
    }

    constraint always_resp_ready {
        cpu_resp_ready == 1;
    }

    function new(string name = "cpu_req_transaction");
        super.new();
    endfunction

    extern virtual function string convert2string();
    extern virtual function bit compare(uvm_object rhs, uvm_comparer = null);
endclass

function string cpu_req_transaction::convert2string();
    string info;
    if (cpu_wr_en) begin
        info = $sformatf("CPU[%0d]: enable: %s, req:%s, req_addr:%0d, wdata=%0d",
                            trans_id, cpu_req_valid?"YES":"NO" ,"WR", cpu_req_addr, cpu_wdata);
    end

    else begin
            info = $sformatf("CPU[%0d]: enable: %s, req:%s, req_addr:%0d",
                            trans_id, cpu_req_valid?"YES":"NO", "RD", cpu_req_addr);
    end
    return info;
endfunction

function bit cpu_req_transaction::compare(uvm_object rhs, uvm_comparer = null);
        cpu_req_transaction tr;
        bit match = 1'b1;

        // 类型检查
        if (!$cast(tr, rhs)) begin
            `error("Type mismatch")
            return 0;
        end
        
        if (cpu_req_valid != tr.cpu_req_valid) begin
            match = 0;
            `info_med($sformatf("valid mismatch: %0h vs %0h",cpu_req_valid, tr.cpu_req_valid))
        end

        if (cpu_wr_en != tr.cpu_wr_en) begin
            match = 0;
            `info_med($sformatf("wr_en mismatch: %0h vs %0h",cpu_wr_en, tr.cpu_wr_en))
        end
        
        if (cpu_req_addr != tr.cpu_req_addr) begin
            match = 0;
            `info_med($sformatf("addr mismatch: %0h vs %0h",cpu_req_addr, tr.cpu_req_addr))
        end

        if (cpu_wdata != tr.cpu_wdata) begin
            match = 0;
            `info_med($sformatf("write data mismatch: %0h vs %0h",cpu_wdata, tr.cpu_wdata))
        end

        if (cpu_resp_ready != tr.cpu_resp_ready) begin
            match = 0;
            `info_med($sformatf("resp ready mismatch: %0h vs %0h",cpu_resp_ready, tr.cpu_resp_ready))
        end
        return match;
endfunction