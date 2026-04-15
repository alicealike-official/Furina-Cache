class cache_transaction extends cache_base_transaction;
    cpu_cache_transaction cpu_cache_tr;
    mem_cache_transaction mem_cache_tr;
    bit hit_sign;
    
    `uvm_object_utils(cache_transaction)
    function new(string name = "cache_transaction");
        super.new();
    endfunction
    extern virtual function string convert2string();
endclass

function string cache_transaction::convert2string();
    if(hit_sign) begin
        return $sformatf("HIT: %s", cpu_tr.convert2string());
    end

    else begin
        return $sformatf("MISS: %s -> %s", cpu_tr.convert2string(), mem_tr.convert2string());
    end
endfunction