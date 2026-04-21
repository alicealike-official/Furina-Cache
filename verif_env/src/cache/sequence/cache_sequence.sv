class cache_sequence extends uvm_sequence #(cache_transaction);
    `uvm_object_utils(cache_sequence)
    
    int num_transactions = 100;

    function new(string name = "cache_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cache_sequence::body();
    cache_transaction tr;
    for (int i = 0; i < num_transactions; i++) begin
        `uvm_do_with(tr, {
            cpu_req == 1;
            cpu_wr_en == 1;
            cpu_req_addr == 0;
        })
    end
endtask