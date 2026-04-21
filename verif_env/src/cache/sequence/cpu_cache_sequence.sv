class cpu_cache_sequence extends uvm_sequence #(cpu_cache_transaction);
    `uvm_object_utils(cpu_cache_sequence)
    
    int num_transactions = 1;

    function new(string name = "cpu_cache_sequence");
        super.new();
    endfunction
// virtual task  pre_start();
//     `uvm_info(get_type_name(), "pre_start called", UVM_LOW)
// endtask

// virtual task  post_start();
//     `uvm_info(get_type_name(), "post_start called", UVM_LOW)
// endtask
    virtual task body();
        cpu_cache_transaction tr;
        for (int i = 0; i < num_transactions; i++) begin
            `uvm_do_with(tr, {
                cpu_req == 1;
                cpu_wr_en == 1;
                cpu_req_addr == 0;
            })
        end
    endtask
endclass