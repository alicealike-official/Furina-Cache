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
// 每轮用完全部槽后再释放；地址依次使用A组、B组、A组，第三轮为A组写入新的数据。
// 新一轮占用期间同时查询旧地址和新地址，响应结束后再查询刚释放的地址。
task wbb_reuse_sequence::run_reuse_round(int round_index);
    int bank;
    int send_target;
    int overlap_before;
    wbb_transaction items[$];
    bit [ADDR_WIDTH-1:0] addr;
    bit [ADDR_WIDTH-1:0] old_addr;

    bank = round_index % 2;
    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
    send_target = obs.send_count + WBB_ENTRIES;
    overlap_before = obs.overlap_count;
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        wbb_transaction tr;

        addr = block_addr(bank * WBB_ENTRIES + index);
        old_addr = block_addr((1 - bank) * WBB_ENTRIES + index);
        tr = wbb_transaction::type_id::create($sformatf("reuse_item_%0d", index));
        tr.addr = addr;
        tr.line_data = make_line(round_index * WBB_ENTRIES + index);
        tr.q0Addr = old_addr;
        tr.q1Addr = addr;
        items.push_back(tr);
    end
    send_group(items);
    round_overlaps[round_index] = obs.overlap_count - overlap_before;
    obs.wait_for_sends(send_target);
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        query(block_addr((1 - bank) * WBB_ENTRIES + index), block_addr(bank * WBB_ENTRIES + index));
    end
    obs.wait_cycles(1);
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
    obs.wait_until_empty();
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        query(block_addr(bank * WBB_ENTRIES + index), block_addr((1 - bank) * WBB_ENTRIES + index));
    end
endtask
