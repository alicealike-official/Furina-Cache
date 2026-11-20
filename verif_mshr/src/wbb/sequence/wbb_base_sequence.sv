class wbb_base_sequence extends uvm_sequence #(wbb_transaction);

    `uvm_object_utils(wbb_base_sequence)

    function new(string name = "wbb_base_sequence");
        super.new(name);
    endfunction

    extern task step(wbb_transaction tr);
    extern task writeback_line(bit [ADDR_WIDTH-1:0] addr,
        bit [LINE_WIDTH-1:0] line_data,
        bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr,
        int unsigned push_delay_cycles = 1);
    extern task query(bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr,
        int unsigned cycles = 1);
    extern task idle_cycles(int unsigned cycles);
    extern task submit_writebacks(wbb_transaction items[$], wbb_input_mode_t mode);

endclass

// 提交一项上游操作并等待 driver 完成：写回等到 push，批量操作等到全部 push，查询/空闲等到指定拍数。
// 返回不代表内存响应已完成；内存写请求和写响应由 DUT 与 memory agent 继续处理。
task wbb_base_sequence::step(wbb_transaction tr);
    if (tr == null) begin
        `fatal("Writeback transaction can not be null")
    end
    start_item(tr);
    finish_item(tr);
endtask

// 统一提交已经生成的一组完整写回：串行逐项完成，流水则交给driver按批次逐拍调度。
// 此处只选择提交方式，不生成地址、数据或查询值；整组push完成后才返回，不等待内存响应。
task wbb_base_sequence::submit_writebacks(wbb_transaction items[$], wbb_input_mode_t mode);
    wbb_batch_transaction batch;
    wbb_batch_transaction nested;

    if (items.size() == 0 || $isunknown(mode) ||
        !(mode inside {WBB_INPUT_SERIAL, WBB_INPUT_PIPELINE})) begin
        `fatal("Writeback group requires entries and a valid input mode", "WBB_INPUT_MODE")
    end
    foreach (items[index]) begin
        if (items[index] == null) begin
            `fatal("Writeback group contains a null entry", "WBB_SEQUENCE_GROUP")
        end
        if ($cast(nested, items[index]) || items[index].operation != WBB_WRITEBACK) begin
            `fatal("Writeback group entries must be ordinary complete writebacks", "WBB_SEQUENCE_GROUP")
        end
    end
    if (mode == WBB_INPUT_PIPELINE) begin
        batch = wbb_batch_transaction::type_id::create("pipeline_group");
        batch.mode = WBB_BATCH_PIPELINED;
        batch.hold_cycles = 0;
        batch.entries = items;
        step(batch);
    end else begin
        foreach (items[index]) begin
            step(items[index]);
        end
    end
endtask

// 使用指定块地址、完整行数据和两个独立查询地址创建写回事务，等待 reserve/push 完成。
// q0Addr/q1Addr 在预留等待和 push 阶段保持；数据内容由调用方指定，sequence 不选择槽位。
// push_delay_cycles 默认1表示预留成功后的下一拍 push，更大值只允许在显式延迟模式使用。
task wbb_base_sequence::writeback_line(bit [ADDR_WIDTH-1:0] addr,
    bit [LINE_WIDTH-1:0] line_data,
    bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr,
    int unsigned push_delay_cycles);
    wbb_transaction tr;
    tr = wbb_transaction::type_id::create("writeback");
    tr.addr = addr;
    tr.line_data = line_data;
    tr.q0Addr = q0Addr;
    tr.q1Addr = q1Addr;
    tr.push_delay_cycles = push_delay_cycles;
    step(tr);
endtask

// 独立设置两个查询地址并保持指定数量的采样拍；期间不提交新 reserve 或 push。
// 内存发送和响应继续运行，可用于观察槽在等待发送、等待响应或释放后的查询结果。
task wbb_base_sequence::query(bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr,
    int unsigned cycles);
    wbb_transaction tr;

    tr = wbb_transaction::type_id::create("query");
    tr.operation = WBB_QUERY;
    tr.q0Addr = q0Addr;
    tr.q1Addr = q1Addr;
    tr.cycles = cycles;
    step(tr);
endtask

// 让上游保持空闲若干采样拍，内存侧继续处理已有事务；cycles为0时不提交任何操作。
task wbb_base_sequence::idle_cycles(int unsigned cycles);
    wbb_transaction tr;

    if (cycles == 0) begin
        return;
    end
    tr = wbb_transaction::type_id::create("idle");
    tr.operation = WBB_IDLE;
    tr.cycles = cycles;
    step(tr);
endtask
