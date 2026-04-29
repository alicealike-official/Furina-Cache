class cpu_tag_match_sequence extends cpu_basic_sequence;
    `uvm_object_utils(cpu_tag_match_sequence)
    
    int num_transactions = 1000;

    function new(string name = "cpu_tag_match_sequence");
        super.new();
    endfunction

    extern virtual task body();
endclass

task cpu_tag_match_sequence::body();
    cpu_req_transaction tr;
    //logic [`DATA_ADDR_BUS-1 : 0] random_addr;

    // assert(std::randomize(random_addr) with {
    // random_addr[1:0] == 2'b00;   // 或者 (random_addr % 4) == 0
    // });

    // `uvm_do_with(tr, {
    //     cpu_req_valid == 1;
    //     cpu_wr_en == 1;
    //     cpu_req_addr == random_addr;
    // })
    
    logic [$clog2(`NUM_CACHE_SET)-1 : 0]                                        random_index;
    logic [$clog2(`CACHE_BLOCK_SIZE)-1 : 0]                                     random_offset;
    logic [`DATA_ADDR_BUS-$clog2(`NUM_CACHE_SET)-$clog2(`CACHE_BLOCK_SIZE)-1:0]  fix_tag;

    std::randomize(fix_tag);

    for (int i = 0; i < num_transactions; i++) begin

        assert(std::randomize(random_offset) with {
        random_offset[1:0] == 2'b00;   // 或者 (random_addr % 4) == 0
        });

        std::randomize(random_index);
        `uvm_do_with(tr, {
            cpu_req_valid == 1;
            cpu_req_addr == {fix_tag, random_index, random_offset};
        })
    end
endtask
