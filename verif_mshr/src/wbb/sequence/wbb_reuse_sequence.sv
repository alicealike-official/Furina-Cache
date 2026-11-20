class wbb_reuse_sequence extends wbb_scenario_sequence;
    int round_overlaps[3] = '{default: 0};

    `uvm_object_utils(wbb_reuse_sequence)

    function new(string name = "wbb_reuse_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task run_reuse_round(int round_index);
endclass

task wbb_reuse_sequence::body();
    for (int round_index = 0; round_index < 3; round_index++) begin
        run_reuse_round(round_index);
    end
endtask

// 每轮生成同一组完整写回，再由公共send_group按串行或流水模式提交。
// 每轮用完全部槽后再释放；两组地址轮换，第三轮再次使用首组地址并写入新数据。
// 新一轮占用期间同时查询旧地址和新地址，响应结束后再查询刚释放的地址。
task wbb_reuse_sequence::run_reuse_round(int round_index);
    int address_group;
    int send_target;
    int overlap_before;
    wbb_transaction items[$];
    bit [ADDR_WIDTH-1:0] addr;
    bit [ADDR_WIDTH-1:0] old_addr;

    // 切换本轮地址组并暂停响应，先保留所有新写回的占用。
    address_group = round_index % 2;
    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
    send_target = obs.send_count + WBB_ENTRIES;
    overlap_before = obs.overlap_count;

    // 为新地址生成本轮数据，同时查询旧地址和新地址。
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        wbb_transaction item;

        addr = block_addr(address_group * WBB_ENTRIES + index);
        old_addr = block_addr((1 - address_group) * WBB_ENTRIES + index);
        item = wbb_transaction::type_id::create($sformatf("reuse_item_%0d", index));
        item.addr = addr;
        item.line_data = make_line(round_index * WBB_ENTRIES + index);
        item.q0Addr = old_addr;
        item.q1Addr = addr;
        items.push_back(item);
    end

    // 完成整批提交，记录流水重叠次数，并等所有请求发送。
    send_group(items);
    round_overlaps[round_index] = obs.overlap_count - overlap_before;
    obs.wait_for_sends(send_target);
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        query(block_addr((1 - address_group) * WBB_ENTRIES + index), block_addr(address_group * WBB_ENTRIES + index));
    end

    // 逐项查询结束后放行响应，再查刚释放的地址，确认旧命中解除。
    obs.wait_cycles(1);
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
    obs.wait_until_empty();
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        query(block_addr(address_group * WBB_ENTRIES + index), block_addr((1 - address_group) * WBB_ENTRIES + index));
    end
endtask
