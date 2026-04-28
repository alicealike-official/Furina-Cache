class cpu_req_sequence extends uvm_sequence #(cpu_req_transaction);
    `uvm_object_utils(cpu_req_sequence)
    
    int num_transactions = 10000;

    function new(string name = "cpu_req_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_req_sequence::body();
    // localparam ADDR_WR_MISS = 32'h0000_0800;  // tag=1, index=0, offset=0
    // localparam ADDR_RD_MISS = 32'h0000_0840;  // tag=1, index=1, offset=0

    cpu_req_transaction tr;

    for (int i = 0; i < num_transactions; i++) begin

        `uvm_do_with(tr, {
            cpu_req_valid == 1;
            cpu_req_addr < 10000;
        })
    end
    // logic [$clog2(`NUM_CACHE_SET)-1:0] index = 0;
    // logic [$clog2(`CACHE_BLOCK_SIZE)-1:0] offset = 0;

    // logic [$clog2(`DATA_ADDR_BUS)-$clog2(`NUM_CACHE_SET)-$clog2(`CACHE_BLOCK_SIZE) - 1:0] tag=1;


    // `uvm_do_with(tr, {
    //     cpu_req_valid   == 1;
    //     cpu_req_addr    == 0;
    //     cpu_wr_en       == 1;
    //     cpu_wdata       == 32'hA5A5_A5A5;
    // })

    // `uvm_do_with(tr, {
    //     cpu_req_valid   == 1;
    //     cpu_req_addr    == {tag, index, offset};
    //     cpu_wr_en       == 1;
    //     cpu_wdata       == 32'hffff_ffff;
    // })
endtask
