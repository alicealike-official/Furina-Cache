// 每轮持续提交4096笔写回；轮内地址唯一，轮间排空后复用地址并更换数据。
class wbb_long_run_sequence extends wbb_scenario_sequence;
    localparam int ROUND_COUNT = 3;
    localparam int LINES_PER_ROUND = 4096;
    localparam int WRITEBACK_COUNT = ROUND_COUNT * LINES_PER_ROUND;
    int round_index = 0;
    int randomized_lines = 0;

    `uvm_object_utils(wbb_long_run_sequence)

    function new(string name = "wbb_long_run_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task prepare_items(int first_index, int count, ref wbb_transaction items[$]);
endclass

// 先制造满槽和发送背压，再持续提交远多于槽数的请求；只在整轮结束后排空。
task wbb_long_run_sequence::body();
    wbb_transaction items[$];

    // 【防御性检查】本场景需要多槽，且预填充后仍有足够的持续流量。
    if (WBB_ENTRIES < 2 || WBB_ENTRIES >= LINES_PER_ROUND) begin
        `fatal("Long run requires multiple slots and more writes than slots", "WBB_CASE_CONFIG")
    end

    // 全部槽先装入数据，暂停内存接收和响应，保留明确的满槽窗口。
    cfg.mem_send_enable = 0;
    cfg.mem_response_enable = 0;
    prepare_items(0, WBB_ENTRIES, items);
    send_group(items);
    obs.wait_cycles(4);

    // 放行内存后连续提交剩余请求；driver在满槽时等待，sequence不逐批排空。
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 1;
    prepare_items(WBB_ENTRIES, LINES_PER_ROUND - WBB_ENTRIES, items);
    send_group(items);
    obs.wait_until_empty();

    // 排空后查询本轮首尾地址，模型和IO断言检查旧占用已经解除。
    query_pairs(block_addr(0), block_addr(LINES_PER_ROUND - 1), block_addr(LINES_PER_ROUND));
endtask

// 生成随机整行及双查询地址；首字标记轮次和地址编号，确保复用时数据版本不同。
// 该方法只准备激励，不读取DUT内部或参考模型。
task wbb_long_run_sequence::prepare_items(int first_index, int count, ref wbb_transaction items[$]);
    bit [LINE_WIDTH-1:0] line_data;
    int unsigned query_index;
    wbb_transaction item;

    items.delete();
    for (int offset = 0; offset < count; offset++) begin
        // 【防御性检查】随机化失败属于激励生成错误，不能继续提交默认数据。
        if (!std::randomize(line_data, query_index) with {
            query_index inside {[0:LINES_PER_ROUND]};
        }) begin
            `fatal("Failed to randomize long-run writeback", "WBB_RANDOMIZE")
        end
        item = wbb_transaction::type_id::create($sformatf("long_item_%0d", first_index + offset));
        item.addr = block_addr(first_index + offset);
        line_data[0 +: DATA_WIDTH] = DATA_WIDTH'(round_index * LINES_PER_ROUND + first_index + offset);
        item.line_data = line_data;
        item.q0Addr = first_index + offset == 0 ? '0 : block_addr(first_index + offset - 1);
        item.q1Addr = block_addr(query_index);
        items.push_back(item);
        randomized_lines++;
    end
endtask
