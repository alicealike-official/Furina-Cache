class wbb_base_sequence extends uvm_sequence #(wbb_transaction);

    `uvm_object_utils(wbb_base_sequence)

    function new(string name = "wbb_base_sequence");
        super.new(name);
    endfunction

    extern task step(wbb_transaction item);
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
task wbb_base_sequence::step(wbb_transaction item);
    // 【防御性检查】确认调用方提供有效对象，避免空句柄被继续访问。
    if (item == null) begin
        `fatal("Writeback transaction can not be null")
    end
    start_item(item);
    finish_item(item);
endtask

// 统一提交已经生成的一组完整写回：串行逐项完成，流水则交给driver按批次逐拍调度。
// 此处只选择提交方式，不生成地址、数据或查询值；整组push完成后才返回，不等待内存响应。
task wbb_base_sequence::submit_writebacks(wbb_transaction items[$], wbb_input_mode_t mode);
    wbb_batch_transaction batch;
    wbb_batch_transaction nested;

    // 【防御性检查】校验批次非空及提交模式合法，检查的是调用参数，不是DUT行为。
    if (items.size() == 0 || $isunknown(mode) ||
        !(mode inside {WBB_INPUT_SERIAL, WBB_INPUT_PIPELINE})) begin
        `fatal("Writeback group requires entries and a valid input mode", "WBB_INPUT_MODE")
    end

    foreach (items[index]) begin
        // 【防御性检查】批次中的每项都必须是已创建的事务对象。
        if (items[index] == null) begin
            `fatal("Writeback group contains a null entry", "WBB_SEQUENCE_GROUP")
        end
        // 【防御性检查】此接口只接收普通写回事务，防止传入嵌套批次或查询/空闲操作。
        if ($cast(nested, items[index]) || items[index].operation != WBB_WRITEBACK) begin
            `fatal("Writeback group entries must be ordinary complete writebacks", "WBB_SEQUENCE_GROUP")
        end
    end

    // 参数检查结束，按指定模式正式提交激励。
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
    wbb_transaction item;
    item = wbb_transaction::type_id::create("writeback");
    item.addr = addr;
    item.line_data = line_data;
    item.q0Addr = q0Addr;
    item.q1Addr = q1Addr;
    item.push_delay_cycles = push_delay_cycles;
    step(item);
endtask

// 独立设置两个查询地址并保持指定数量的采样拍；期间不提交新 reserve 或 push。
// 内存发送和响应继续运行，可用于观察槽在等待发送、等待响应或释放后的查询结果。
task wbb_base_sequence::query(bit [ADDR_WIDTH-1:0] q0Addr, bit [ADDR_WIDTH-1:0] q1Addr,
    int unsigned cycles);
    wbb_transaction item;

    item = wbb_transaction::type_id::create("query");
    item.operation = WBB_QUERY;
    item.q0Addr = q0Addr;
    item.q1Addr = q1Addr;
    item.cycles = cycles;
    step(item);
endtask

// 让上游保持空闲若干采样拍，内存侧继续处理已有事务；cycles为0时不提交任何操作。
task wbb_base_sequence::idle_cycles(int unsigned cycles);
    wbb_transaction item;

    if (cycles == 0) begin
        return;
    end
    item = wbb_transaction::type_id::create("idle");
    item.operation = WBB_IDLE;
    item.cycles = cycles;
    step(item);
endtask
