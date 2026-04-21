class mem_cache_sequence extends uvm_sequence #(mem_cache_transaction);
    `uvm_object_utils(mem_cache_sequence)
    
    int num_transactions = 1;
    
    function new(string name = "mem_cache_sequence");
        super.new();
    endfunction

    virtual task body();
        mem_cache_transaction tr;
        for (int i = 0; i < num_transactions; i++) begin
            `uvm_do_with(tr,{
            })
        end
    endtask
endclass