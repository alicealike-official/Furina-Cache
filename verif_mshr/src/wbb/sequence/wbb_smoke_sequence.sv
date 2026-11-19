// 基础case的两笔写回：不同块地址、不同整行数据，两个查询口分别指向当前块和另一个块。
class wbb_smoke_sequence extends wbb_base_sequence;
    `uvm_object_utils(wbb_smoke_sequence)

    function new(string name = "wbb_smoke_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

task wbb_smoke_sequence::body();
    bit [ADDR_WIDTH-1:0] addr;
    bit [ADDR_WIDTH-1:0] query_addr;
    bit [LINE_WIDTH-1:0] line_data;

    for (int index = 0; index < 2; index++) begin
        addr = ADDR_WIDTH'((index + 1) * BLOCK_SIZE);
        query_addr = ADDR_WIDTH'((2 - index) * BLOCK_SIZE);
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            line_data[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'((index + 1) * 'h10000000 + word_index);
        end
        writeback_line(addr, line_data, addr, query_addr);
    end
endtask
