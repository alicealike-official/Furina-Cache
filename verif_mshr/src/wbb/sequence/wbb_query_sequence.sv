class wbb_query_sequence extends wbb_scenario_sequence;
    `uvm_object_utils(wbb_query_sequence)

    function new(string name = "wbb_query_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task run_query_round(int round_index);
    extern function void prepare_query_items(int round_index, output wbb_transaction writebacks[$]);
    extern function void set_serial_queries(wbb_transaction item, int first_index, int item_index);
    extern function void set_pipeline_queries(wbb_transaction item, int first_index,
        int item_index, int round_index);
endclass

task wbb_query_sequence::body();
    // 【防御性检查】确认当前容量足以构造本场景，不代表DUT功能结果检查。
    if (WBB_ENTRIES < 2) begin
        `fatal("Dual-slot query scenarios require at least two WBB entries", "WBB_QUERY_CONFIG")
    end
    // 【防御性检查】流水查询组合需要足够槽位，先确认本配置能构造该场景。
    if (cfg.input_mode == WBB_INPUT_PIPELINE && WBB_ENTRIES < 4) begin
        `fatal("Pipelined query combinations require at least four WBB entries", "WBB_QUERY_CONFIG")
    end

    for (int round_index = 0; round_index < 2; round_index++) begin
        run_query_round(round_index);
    end
endtask

// 先让数据停在待发送阶段查询，再让它们发送但不响应继续查询，最后响应全部完成后查旧地址。
// reserve/push期间使用不同查询组合，确保尚未push的地址也被查询到；两个输入模式复用同一阶段安排。
task wbb_query_sequence::run_query_round(int round_index);
    wbb_transaction writebacks[$];
    int first_index;
    int send_target;
    bit [ADDR_WIDTH-1:0] first_addr;
    bit [ADDR_WIDTH-1:0] last_addr;
    bit [ADDR_WIDTH-1:0] miss_addr;

    // 选择本轮首尾两笔写回地址，以及一个不会被本轮写回占用的地址。
    first_index = round_index * WBB_ENTRIES;
    first_addr = block_addr(first_index);
    last_addr = block_addr(first_index + WBB_ENTRIES - 1);
    miss_addr = block_addr(1000);

    // 暂停内存接收和响应，记录本轮全部发送后应达到的累计发送数。
    obs.wait_cycles(1);
    cfg.mem_send_enable = 0;
    cfg.mem_response_enable = 0;
    send_target = obs.send_count + WBB_ENTRIES;

    // 完成N笔reserve/push：提交期间观察reserved查询，随后检查pending阶段。
    prepare_query_items(round_index, writebacks);
    send_group(writebacks);
    query_pairs(first_addr, last_addr, miss_addr);

    // 允许发送但继续扣住响应；全部发送后，issued地址仍应被查询命中。
    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    obs.wait_for_sends(send_target);
    query_pairs(first_addr, last_addr, miss_addr);

    // 按FIFO顺序放行响应并排空，再查询相同地址，确认旧占用已解除。
    obs.wait_cycles(1);
    cfg.mem_response_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    obs.wait_until_empty();
    query_pairs(first_addr, last_addr, miss_addr);
endtask

// 生成一轮N笔互异地址和数据，再按输入模式设置两路查询地址；数据生成逻辑只有这一份。
function void wbb_query_sequence::prepare_query_items(int round_index, output wbb_transaction writebacks[$]);
    wbb_transaction item;
    int first_index;

    // 清空输出队列，并确定本轮地址与数据使用的起始编号。
    writebacks.delete();
    first_index = round_index * WBB_ENTRIES;

    for (int item_index = 0; item_index < WBB_ENTRIES; item_index++) begin
        // 为每笔写回准备互异的块地址和整行数据。
        item = wbb_transaction::type_id::create($sformatf("query_fill_%0d", item_index));
        item.addr = block_addr(first_index + item_index);
        item.line_data = make_line(first_index + item_index);

        // 按提交方式选择查询组合，再加入本轮待发送队列。
        if (cfg.input_mode == WBB_INPUT_SERIAL) begin
            set_serial_queries(item, first_index, item_index);
        end else begin
            set_pipeline_queries(item, first_index, item_index, round_index);
        end
        writebacks.push_back(item);
    end
endfunction

// 串行事务的查询地址从reserve保持到push，直接查询自身即可看到reserved阶段。
function void wbb_query_sequence::set_serial_queries(wbb_transaction item, int first_index, int item_index);
    bit [ADDR_WIDTH-1:0] miss_addr;

    miss_addr = block_addr(1000);
    case ((first_index + item_index) % 4)
        0: begin
            // 两口同时查询当前写回地址。
            item.q0Addr = item.addr;
            item.q1Addr = item.addr;
        end
        1: begin
            // 只有q0查询当前写回，q1查询未占用地址。
            item.q0Addr = item.addr;
            item.q1Addr = miss_addr;
        end
        2: begin
            // 交换两口，覆盖只有q1命中的组合。
            item.q0Addr = miss_addr;
            item.q1Addr = item.addr;
        end
        3: begin
            // 同时查询当前写回和本轮首笔写回，检查不同地址独立匹配。
            item.q0Addr = item.addr;
            item.q1Addr = block_addr(first_index);
        end
    endcase
endfunction

// 流水时查询对来自当前reserve项，因此查询上一笔正要push的地址来命中reserved。
// 第一轮覆盖reserved双命中和左右单命中，第二轮补上reserved与另一个pending地址同时命中。
function void wbb_query_sequence::set_pipeline_queries(wbb_transaction item, int first_index,
    int item_index, int round_index);
    bit [ADDR_WIDTH-1:0] reserved_addr;
    bit [ADDR_WIDTH-1:0] miss_addr;

    // 首笔前面没有旧预留；q0查未占用地址，q1查本笔地址。
    miss_addr = block_addr(1000);
    if (item_index == 0) begin
        item.q0Addr = miss_addr;
        item.q1Addr = item.addr;
        return;
    end

    // 后续提交与上一笔push重叠；该采样沿之前，上一笔地址仍处于reserved阶段。
    reserved_addr = block_addr(first_index + item_index - 1);
    case ((item_index - 1) % 3)
        0: begin
            // 两口同时查询旧预留地址。
            item.q0Addr = reserved_addr;
            item.q1Addr = reserved_addr;
        end
        1: begin
            // q0查旧预留；q1第一轮查未占用地址，第二轮查已push的首笔地址。
            item.q0Addr = reserved_addr;
            item.q1Addr = round_index == 0 ? miss_addr : block_addr(first_index);
        end
        2: begin
            // 交换两口，覆盖q1查询旧预留的相应组合。
            item.q0Addr = round_index == 0 ? miss_addr : block_addr(first_index);
            item.q1Addr = reserved_addr;
        end
    endcase
endfunction
