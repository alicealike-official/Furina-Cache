// 先让槽0完成发送，再从槽1开始积累整组待发数据，统一放行后观察连续发送及回绕。
class wbb_arbitration_sequence extends wbb_scenario_sequence;
    localparam int WRITEBACK_COUNT = WBB_ENTRIES + 1;
    int pending_before_release;
    int burst_start;

    `uvm_object_utils(wbb_arbitration_sequence)

    function new(string name = "wbb_arbitration_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

task wbb_arbitration_sequence::body();
    int first_send;
    int first_id;

    // 【防御性检查】确认当前容量足以构造本场景，不代表DUT功能结果检查。
    if (WBB_ENTRIES < 2) begin
        `fatal("Arbitration case requires at least two slots", "WBB_CASE_CONFIG")
    end
    first_send = obs.send_count;
    send_line(0);
    obs.wait_for_sends(first_send + 1);
    first_id = obs.send_ids[first_send];
    cfg.mem_send_enable = 0;

    for (int index = 1; index < WBB_ENTRIES; index++) begin
        send_line(index);
    end
    release_response(first_id);
    send_line(WBB_ENTRIES);
    obs.wait_cycles(2);
    pending_before_release = $countones(obs.loaded & ~obs.issued);
    burst_start = obs.send_count;

    // 所有槽都已有数据后才统一允许发送，避免用上游提交速度判断下游吞吐。
    cfg.mem_send_enable = 1;
    obs.wait_for_sends(burst_start + WBB_ENTRIES);
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
endtask
