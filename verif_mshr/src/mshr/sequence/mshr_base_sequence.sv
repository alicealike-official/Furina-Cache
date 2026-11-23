class mshr_base_sequence extends uvm_sequence #(mshr_transaction);

    `uvm_object_utils(mshr_base_sequence)

    function new(string name = "mshr_base_sequence");
        super.new(name);
    endfunction

    extern task step(mshr_transaction item);
    extern task query(bit [TAG_WIDTH-1:0] q0Tag, bit [INDEX_WIDTH-1:0] q0Index,
        bit [TAG_WIDTH-1:0] q1Tag, bit [INDEX_WIDTH-1:0] q1Index,
        int unsigned cycles = 1);
    extern task idle_cycles(int unsigned cycles);

endclass

// 提交一项上游操作，等待driver完成该次alloc/merge或指定拍数的查询/空闲。
// 不等待内存响应、fill或replay，后续请求可以继续进入其他Entry或同Entry的下一个Slot。
task mshr_base_sequence::step(mshr_transaction item);
    // 【防御性检查】确认调用方提供有效对象，避免空句柄被继续访问。
    if (item == null) begin
        `fatal("MSHR transaction can not be null", "MSHR_SEQUENCE")
    end
    start_item(item);
    finish_item(item);
endtask

// 独立设置两路查询并保持指定数量的采样拍；不生成alloc/merge，其他通道继续运行。
task mshr_base_sequence::query(bit [TAG_WIDTH-1:0] q0Tag, bit [INDEX_WIDTH-1:0] q0Index,
    bit [TAG_WIDTH-1:0] q1Tag, bit [INDEX_WIDTH-1:0] q1Index,
    int unsigned cycles);
    mshr_transaction item;

    item = mshr_transaction::type_id::create("query");
    item.operation = MSHR_QUERY;
    item.q0Tag = q0Tag;
    item.q0Index = q0Index;
    item.q1Tag = q1Tag;
    item.q1Index = q1Index;
    item.cycles = cycles;
    step(item);
endtask

// 上游保持空闲若干采样拍；cycles为0时直接返回，不向driver提交空操作。
task mshr_base_sequence::idle_cycles(int unsigned cycles);
    mshr_transaction item;

    if (cycles == 0) begin
        return;
    end
    item = mshr_transaction::type_id::create("idle");
    item.operation = MSHR_IDLE;
    item.cycles = cycles;
    step(item);
endtask
