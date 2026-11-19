// 一项批量操作包含多笔完整写回，用于显式延迟 push 模式下构造多个槽都只预留的状态。
// driver 先预留全部 entries，再等待 hold_cycles 拍，最后逐笔 push；整批完成后才 item_done。
class wbb_batch_transaction extends wbb_transaction;
    wbb_transaction entries[$];
    int unsigned hold_cycles = 4;

    `uvm_object_utils_begin(wbb_batch_transaction)
        `uvm_field_queue_object(entries, UVM_DEFAULT)
        `uvm_field_int(hold_cycles, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "wbb_batch_transaction");
        super.new(name);
    endfunction

endclass
