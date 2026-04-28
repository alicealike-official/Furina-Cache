class cpu_basic_sequence extends uvm_sequence #(cpu_req_transaction);
    `uvm_object_utils(cpu_basic_sequence)
    
    int num_transactions = 10000;

    function new(string name = "cpu_basic_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_basic_sequence::body();

    cpu_req_transaction tr;

    for (int i = 0; i < num_transactions; i++) begin

        `uvm_do_with(tr, {
            cpu_req_valid == 1;
        })
    end
endtask
