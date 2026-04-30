class cpu_fill_full_sequence extends cpu_basic_sequence;
    `uvm_object_utils(cpu_fill_full_sequence)
    
    int num_transactions = 1000;

    function new(string name = "cpu_fill_full_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_fill_full_sequence::body();
    cpu_req_transaction tr;
    logic [$clog2(`NUM_CACHE_SET)-1 : 0]                                        random_index;
    logic [$clog2(`CACHE_BLOCK_SIZE)-1 : 0]                                     random_offset;
    logic [`DATA_ADDR_BUS-$clog2(`NUM_CACHE_SET)-$clog2(`CACHE_BLOCK_SIZE)-1:0] random_tag;

    for (int i=0; i<`NUM_CACHE_SET; i++) begin
        for(int j=0; j<`NUM_CACHE_WAY; j++) begin
            random_index = i;
            std::randomize(random_tag);
            std::randomize(random_offset) with {
                random_offset[1:0] == 2'b00;
            };

            `uvm_do_with(tr, 
            {
                cpu_req_valid == 1;
                cpu_req_addr == {random_tag, random_index, random_offset};
            })
        end
    end

    for (int i = 0; i < num_transactions; i++) begin
        `uvm_do_with(tr, {
            cpu_req_valid == 1;
        })
    end

endtask
