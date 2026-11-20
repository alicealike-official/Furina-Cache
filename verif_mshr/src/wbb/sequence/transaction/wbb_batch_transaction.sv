typedef enum int {
    WBB_BATCH_DEFERRED,
    WBB_BATCH_PIPELINED
} wbb_batch_mode_t;

// 一项批量操作包含多笔完整写回，整批 push 完成后才 item_done。
// DEFERRED 先全部预留再等待、逐笔 push；PIPELINED 让旧事务的 push 与新事务的 reserve 同拍。
class wbb_batch_transaction extends wbb_transaction;
    wbb_transaction entries[$];
    wbb_batch_mode_t mode = WBB_BATCH_DEFERRED;
    // 只用于 DEFERRED；PIPELINED 必须显式设为0，且每笔成功预留的下一拍就 push。
    int unsigned hold_cycles = 4;

    `uvm_object_utils_begin(wbb_batch_transaction)
        `uvm_field_queue_object(entries, UVM_DEFAULT)
        `uvm_field_enum(wbb_batch_mode_t, mode, UVM_DEFAULT)
        `uvm_field_int(hold_cycles, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "wbb_batch_transaction");
        super.new(name);
    endfunction

endclass
