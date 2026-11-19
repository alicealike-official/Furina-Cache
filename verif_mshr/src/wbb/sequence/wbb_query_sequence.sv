class wbb_query_sequence extends wbb_scenario_sequence;
    `uvm_object_utils(wbb_query_sequence)

    function new(string name = "wbb_query_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task run_query_round(int round_index);
endclass

task wbb_query_sequence::body();
    if (WBB_ENTRIES < 2) begin
        `fatal("Dual-slot query scenarios require at least two WBB entries", "WBB_QUERY_CONFIG")
    end
    for (int round_index = 0; round_index < 2; round_index++) begin
        run_query_round(round_index);
    end
endtask

// 先让数据停在待发送阶段查询，再让它们发送但不响应继续查询，最后响应全部完成后查旧地址。
// reserve/push期间使用不同查询组合，确保尚未push的地址也被查询到。
task wbb_query_sequence::run_query_round(int round_index);
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
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        case ((first + index) % 4)
            0: send_line(first + index, block_addr(first + index), block_addr(first + index));
            1: send_line(first + index, block_addr(first + index), miss);
            2: send_line(first + index, miss, block_addr(first + index));
            3: send_line(first + index, block_addr(first + index), a);
        endcase
    end
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
