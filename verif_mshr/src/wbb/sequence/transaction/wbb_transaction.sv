typedef enum int {
    WBB_WRITEBACK,
    WBB_QUERY,
    WBB_IDLE
} wbb_operation_t;

class wbb_transaction extends uvm_sequence_item;
    // 默认是一笔完整写回；查询和空闲操作只控制查询地址及等待拍数，不产生 reserve/push。
    wbb_operation_t operation = WBB_WRITEBACK;
    // reserve 在第 k 拍成功时，push 在第 k+push_delay_cycles 拍发生，默认严格下一拍。
    int unsigned push_delay_cycles = 1;
    // QUERY/IDLE 操作保持的采样拍数；这些控制字段不随机化，避免改变已有数据随机激励。
    int unsigned cycles = 1;
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
        `uvm_field_enum(wbb_operation_t, operation, UVM_DEFAULT)
        `uvm_field_int(push_delay_cycles, UVM_DEFAULT)
        `uvm_field_int(cycles, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(line_data, UVM_DEFAULT)
        `uvm_field_int(q0Addr, UVM_DEFAULT)
        `uvm_field_int(q1Addr, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "wbb_transaction");
        super.new(name);
    endfunction

endclass
