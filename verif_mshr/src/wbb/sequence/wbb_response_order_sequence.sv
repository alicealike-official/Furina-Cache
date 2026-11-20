// 先接收整组写请求，再按实际发送ID的逆序逐个返回响应，并查询释放与保留的地址。
class wbb_response_order_sequence extends wbb_scenario_sequence;
    localparam int WRITEBACK_COUNT = WBB_ENTRIES;
    int expected_ids[$];
    int response_start;

    `uvm_object_utils(wbb_response_order_sequence)

    function new(string name = "wbb_response_order_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

task wbb_response_order_sequence::body();
    int send_start;
    int id;
    bit [ADDR_WIDTH-1:0] released_addr;
    bit [ADDR_WIDTH-1:0] remaining_addr;

    if (WBB_ENTRIES < 2) begin
        `fatal("Response reordering requires at least two slots", "WBB_CASE_CONFIG")
    end

    // 保存计数起点并填入全部槽，等待每笔都已发送。
    send_start = obs.send_count;
    response_start = obs.response_count;
    expected_ids.delete();
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        send_line(index);
    end
    obs.wait_for_sends(send_start + WBB_ENTRIES);

    // 按实际发送ID逆序放行响应，并对照查询已释放地址和仍占用地址。
    for (int index = WBB_ENTRIES - 1; index >= 0; index--) begin
        id = obs.send_ids[send_start + index];
        released_addr = obs.slot_addr[id];
        remaining_addr = index > 0 ? obs.slot_addr[obs.send_ids[send_start]] : block_addr(WBB_ENTRIES + 1);
        expected_ids.push_back(id);
        release_response(id);
        // q0 应已不再命中释放的地址，q1 在仍有旧请求时继续查询一个未释放的槽。
        query(released_addr, remaining_addr, 2);
    end

    // 恢复默认响应策略，交给公共收尾检查等待全部完成。
    obs.wait_cycles(1);
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
endtask
