class cpu_cache_sequence extends uvm_sequence #(cpu_cache_transaction);
    `uvm_object_utils(cpu_cache_sequence)
    
    int num_transactions = 20;

    function new(string name = "cpu_cache_sequence");
        super.new();
    endfunction

    virtual task body();
        cpu_cache_transaction tr;
        for (int i = 0; i < num_transactions; i++) begin
            `uvm_do_with(tr, {
                cpu_req == 1;
            })
        end
    endtask
endclass