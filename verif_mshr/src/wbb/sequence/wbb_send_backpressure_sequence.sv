// 先让发送选择跨过最后一个槽，再在背压期间加入更靠前的新候选，检查挂起请求不会被替换。
class wbb_send_backpressure_sequence extends wbb_scenario_sequence;
    localparam int WRITEBACK_COUNT = WBB_ENTRIES + 2;
    int stalled_id;
    int competing_id;
    bit stalled_before_insert;
    bit stalled_after_insert;

    `uvm_object_utils(wbb_send_backpressure_sequence)

    function new(string name = "wbb_send_backpressure_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

task wbb_send_backpressure_sequence::body();
    int send_start;

    // 【防御性检查】确认当前容量足以构造本场景，不代表DUT功能结果检查。
    if (WBB_ENTRIES < 2) begin
        `fatal("Backpressure insertion requires at least two slots", "WBB_CASE_CONFIG")
    end

    // 先让发送顺序经过全部槽，选出随后要挂起和插入竞争的槽位。
    send_start = obs.send_count;
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        send_line(index);
    end
    obs.wait_for_sends(send_start + WBB_ENTRIES);
    stalled_id = obs.send_ids[send_start + WBB_ENTRIES - 1];
    competing_id = obs.send_ids[send_start];

    // 此时没有待发数据，先停止接收新的 send，再只释放最后发送的那个槽。
    cfg.mem_send_enable = 0;
    release_response(stalled_id);
    send_line(WBB_ENTRIES);
    obs.wait_cycles(3);
    stalled_before_insert = obs.last_sample.send_valid === 1'b1 &&
        obs.last_sample.send_ready === 1'b0 &&
        obs.last_sample.send_payload_id === BUS_ID_WIDTH'(stalled_id);

    // 旧请求已经挂起，再释放更靠前的槽并写入另一行；原请求必须继续保持。
    release_response(competing_id);
    send_line(WBB_ENTRIES + 1);
    obs.wait_cycles(3);
    stalled_after_insert = obs.last_sample.send_valid === 1'b1 &&
        obs.last_sample.send_ready === 1'b0;

    // 恢复内存接收和响应，让两笔新写回及之前保留的事务全部完成。
    cfg.mem_send_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
endtask
