class wbb_transaction extends uvm_sequence_item;
    // 一笔完整的上游写回事务，由 driver 展开为 reserve 和 push 两个阶段。
    rand bit [ADDR_WIDTH-1:0] addr;
    rand bit [LINE_WIDTH-1:0] line_data;
    rand bit [ADDR_WIDTH-1:0] q0Addr;
    rand bit [ADDR_WIDTH-1:0] q1Addr;

    constraint block_aligned {
        addr % BLOCK_SIZE == 0;
        q0Addr % BLOCK_SIZE == 0;
        q1Addr % BLOCK_SIZE == 0;
    }

    `uvm_object_utils_begin(wbb_transaction)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(line_data, UVM_DEFAULT)
        `uvm_field_int(q0Addr, UVM_DEFAULT)
        `uvm_field_int(q1Addr, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "wbb_transaction");
        super.new(name);
    endfunction

endclass
