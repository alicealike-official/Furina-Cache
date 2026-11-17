class wbb_base_sequence extends uvm_sequence #(wbb_transaction);

    `uvm_object_utils(wbb_base_sequence)

    function new(string name = "wbb_base_sequence");
        super.new(name);
    endfunction

    extern task step(wbb_transaction tr);
    extern task writeback_line(bit [ADDR_WIDTH-1:0] addr,
        bit [LINE_WIDTH-1:0] line_data,
        bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr);

endclass

// 提交一笔完整写回事务，等待 driver 完成 reserve 和 push 后调用 item_done()。
// 返回只表示数据已交给 WBB；内存写请求和写响应由 DUT 与 memory agent 继续处理。
task wbb_base_sequence::step(wbb_transaction tr);
    if (tr == null) begin
        `fatal("Writeback transaction can not be null")
    end
    start_item(tr);
    finish_item(tr);
endtask

// 使用指定块地址、完整行数据和两个独立查询地址创建写回事务，等待 reserve/push 完成。
// q0Addr/q1Addr 在本笔事务的预留等待和 push 阶段保持，不要求与写回地址相同。
// 数据图样由调用方决定，sequence 不选择槽位，也不单独提交 reserve 或 push。
task wbb_base_sequence::writeback_line(bit [ADDR_WIDTH-1:0] addr,
    bit [LINE_WIDTH-1:0] line_data,
    bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr);
    wbb_transaction tr;
    tr = wbb_transaction::type_id::create("writeback");
    tr.addr = addr;
    tr.line_data = line_data;
    tr.q0Addr = q0Addr;
    tr.q1Addr = q1Addr;
    step(tr);
endtask
