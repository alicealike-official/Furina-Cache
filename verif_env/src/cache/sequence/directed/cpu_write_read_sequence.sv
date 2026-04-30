class cpu_write_read_sequence extends cpu_basic_sequence;
    `uvm_object_utils(cpu_write_read_sequence)
    
    int num_transactions = 1000;

    function new(string name = "cpu_write_read_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_write_read_sequence::body();
    cpu_req_transaction tr;
    logic [`DATA_ADDR_BUS-1 : 0] random_addr;

    std::randomize(random_addr) with {
    random_addr[1:0] == 2'b00;   // 或者 (random_addr % 4) == 0
    };
    
    for (int i = 0; i < num_transactions; i++) begin

        `uvm_do_with(tr, {
            cpu_req_valid == 1;
            cpu_req_addr == random_addr;
        })
    end
endtask
