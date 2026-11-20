class wbb_query_sequence extends wbb_scenario_sequence;
    `uvm_object_utils(wbb_query_sequence)

    function new(string name = "wbb_query_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task run_query_round(int round_index);
    extern function void prepare_query_items(int round_index, output wbb_transaction items[$]);
    extern function void set_serial_queries(wbb_transaction tr, int first, int index);
    extern function void set_pipeline_queries(wbb_transaction tr, int first, int index, int round_index);
endclass

task wbb_query_sequence::body();
    if (WBB_ENTRIES < 2) begin
        `fatal("Dual-slot query scenarios require at least two WBB entries", "WBB_QUERY_CONFIG")
    end
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
    wbb_transaction items[$];
    int first;
    int send_target;
    bit [ADDR_WIDTH-1:0] a;
    bit [ADDR_WIDTH-1:0] b;
    bit [ADDR_WIDTH-1:0] miss;

    first = round_index * WBB_ENTRIES;
    a = block_addr(first);
    b = block_addr(first + WBB_ENTRIES - 1);
    miss = block_addr(1000);
    obs.wait_cycles(1);
    cfg.mem_send_enable = 0;
    cfg.mem_response_enable = 0;
    send_target = obs.send_count + WBB_ENTRIES;
    prepare_query_items(round_index, items);
    send_group(items);
    query_pairs(a, b, miss);
    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    obs.wait_for_sends(send_target);
    query_pairs(a, b, miss);
    obs.wait_cycles(1);
    cfg.mem_response_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    obs.wait_until_empty();
    query_pairs(a, b, miss);
endtask

// 生成一轮N笔互异地址和数据，再按输入模式设置两路查询地址；数据生成逻辑只有这一份。
function void wbb_query_sequence::prepare_query_items(int round_index, output wbb_transaction items[$]);
    wbb_transaction tr;
    int first;

    items.delete();
    first = round_index * WBB_ENTRIES;
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        tr = wbb_transaction::type_id::create($sformatf("query_fill_%0d", index));
        tr.addr = block_addr(first + index);
        tr.line_data = make_line(first + index);
        if (cfg.input_mode == WBB_INPUT_SERIAL) begin
            set_serial_queries(tr, first, index);
        end else begin
            set_pipeline_queries(tr, first, index, round_index);
        end
        items.push_back(tr);
    end
endfunction

// 串行事务的查询地址从reserve保持到push，直接查询自身即可看到reserved阶段。
function void wbb_query_sequence::set_serial_queries(wbb_transaction tr, int first, int index);
    bit [ADDR_WIDTH-1:0] miss;

    miss = block_addr(1000);
    case ((first + index) % 4)
        0: begin
            tr.q0Addr = tr.addr;
            tr.q1Addr = tr.addr;
        end
        1: begin
            tr.q0Addr = tr.addr;
            tr.q1Addr = miss;
        end
        2: begin
            tr.q0Addr = miss;
            tr.q1Addr = tr.addr;
        end
        3: begin
            tr.q0Addr = tr.addr;
            tr.q1Addr = block_addr(first);
        end
    endcase
endfunction

// 流水时查询对来自当前reserve项，因此查询上一笔正要push的地址来命中reserved。
// 第一轮覆盖reserved双命中和左右单命中，第二轮补上reserved与另一个pending地址同时命中。
function void wbb_query_sequence::set_pipeline_queries(wbb_transaction tr, int first, int index, int round_index);
    bit [ADDR_WIDTH-1:0] previous_addr;
    bit [ADDR_WIDTH-1:0] miss;

    miss = block_addr(1000);
    if (index == 0) begin
        tr.q0Addr = miss;
        tr.q1Addr = tr.addr;
        return;
    end
    previous_addr = block_addr(first + index - 1);
    case ((index - 1) % 3)
        0: begin
            tr.q0Addr = previous_addr;
            tr.q1Addr = previous_addr;
        end
        1: begin
            tr.q0Addr = previous_addr;
            tr.q1Addr = round_index == 0 ? miss : block_addr(first);
        end
        2: begin
            tr.q0Addr = round_index == 0 ? miss : block_addr(first);
            tr.q1Addr = previous_addr;
        end
    endcase
endfunction
