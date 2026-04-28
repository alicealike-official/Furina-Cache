class cpu_read_miss_sequence extends cpu_basic_sequence;
    `uvm_object_utils(cpu_read_miss_sequence)
    
    int num_transactions = 1000;
    logic [`DATA_ADDR_BUS-1 : 0] start_addr = 0;

    constraint addr_range {
        start_addr + (num_transactions-1)*`CACHE_BLOCK_SIZE < 2**`DATA_ADDR_BUS;
    }

    function new(string name = "cpu_read_miss_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_read_miss_sequence::body();
    cpu_req_transaction tr;
    logic [`DATA_ADDR_BUS-1 : 0] current_addr;

    for (int i = 0; i < num_transactions; i++) begin
        current_addr = start_addr + i*`CACHE_BLOCK_SIZE;
        `uvm_do_with(tr, {
            cpu_req_valid == 1;
            cpu_wr_en == 0;
            cpu_req_addr == current_addr;
        })
    end
endtask