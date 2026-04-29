class cpu_fifo_fill_sequence extends cpu_basic_sequence;
    `uvm_object_utils(cpu_fifo_fill_sequence)
    
    int num_transactions = 1000;

    function new(string name = "cpu_fifo_fill_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_fifo_fill_sequence::body();
    cpu_req_transaction tr;
    logic [$clog2(`NUM_CACHE_SET)-1 : 0]                                        random_index;
    logic [$clog2(`CACHE_BLOCK_SIZE)-1 : 0]                                     random_offset;
    logic [`DATA_ADDR_BUS-$clog2(`NUM_CACHE_SET)-$clog2(`CACHE_BLOCK_SIZE)-1:0] random_tag;

    //选取特定的index
    std::randomize(random_index);


    //先填满一路的fifo
    for(int j=0; j<`NUM_CACHE_WAY; j++) begin
        std::randomize(random_tag);
        assert(std::randomize(random_offset) with {
            random_offset[1:0] == 2'b00;
        });
        `uvm_do_with(tr, 
        {
            cpu_req_valid == 1;
            cpu_req_addr == {random_tag, random_index, random_offset};
        })
    end

    for (int i = 0; i < num_transactions; i++) begin
        std::randomize(random_tag);
        assert(std::randomize(random_offset) with {
            random_offset[1:0] == 2'b00;
        });
        `uvm_do_with(tr, {
            cpu_req_valid == 1;
            cpu_req_addr == {random_tag, random_index, random_offset};
        })
    end

endtask
