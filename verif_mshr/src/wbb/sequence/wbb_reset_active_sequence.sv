// 本地非空复位；已发送场景保持外部旧响应静默，不验迟到响应处理。
class wbb_reset_active_sequence extends wbb_reset_sequence;
    wbb_config cfg;
    `uvm_object_utils(wbb_reset_active_sequence)
    function new(string name = "wbb_reset_active_sequence");
        super.new(name);
    endfunction
    // 在本地占用存在时停钟断言；已发送场景须保持外部响应静默，只观察本地清空。
    task reset_local_state(bit no_external_pending = 1);
        longint edge_before;
        if (no_external_pending) begin
            results.check_count("WBB external writes must already be complete", obs.send_count, obs.response_count);
        end else begin
            results.check_condition(vif.memWriteResp_valid === 1'b0, "Local issued reset requires a silent response source");
        end
        clock_driver.assert_reset(1);
        pulses++;
        edge_before = clock_driver.rising_edges;
        check_empty();
        #(clock_driver.cfg.clock_period * 3.0);
        check_empty();
        results.check_count("WBB active reset has no clock edge", clock_driver.rising_edges, edge_before);
        clock_driver.release_reset();
    endtask
    // 预留成功后在下一次push接受之前停钟并复位，明确命中RESERVED窗口。
    task reset_reserved();
        cfg.mem_send_enable = 0;
        fork
            transfer(100);
            begin
                do @(vif.mon_cb); while (!(vif.mon_cb.reserve_en && vif.mon_cb.reserveOk));
                results.check_condition(vif.mon_cb.push_en === 1'b0, "Reserved reset missed pre-push window");
                reset_local_state();
            end
        join
    endtask
    // 所有槽均已push但send被阻塞，复位前必须观察到full及挂起发送。
    task reset_pending();
        cfg.mem_send_enable = 0;
        for (int index = 0; index < WBB_ENTRIES; index++) transfer(200+index);
        obs.wait_cycles(2);
        results.check_condition(vif.full === 1'b1 && vif.send_valid === 1'b1,
            "Pending reset did not reach full WBB with stalled send");
        reset_local_state();
    endtask
    // 每次复位后重新占满并释放全部槽，确认本地取消没有造成容量永久减少。
    task refill_all(int first_line);
        cfg.mem_send_enable = 0;
        for (int index = 0; index < WBB_ENTRIES; index++) transfer(first_line+index);
        obs.wait_cycles(1);
        results.check_condition(vif.full === 1'b1, "WBB lost capacity after reset");
        cfg.mem_send_enable = 1;
        cfg.mem_response_enable = 1;
        obs.wait_until_empty();
    endtask
    // 已发送未确认时仅测本地清空；TB保持旧响应静默，不测试迟到响应进入新事务的行为。
    task reset_issued();
        int target_sends;
        cfg.mem_send_enable = 1;
        cfg.mem_response_enable = 0;
        target_sends = obs.send_count + WBB_ENTRIES;
        for (int index = 0; index < WBB_ENTRIES; index++) transfer(500+index);
        obs.wait_for_sends(target_sends);
        results.check_condition((&obs.issued) === 1'b1 && vif.full === 1'b1,
            "Issued reset did not reach all slots awaiting acknowledgement");
        reset_local_state(0);
    endtask
    // 明确记录本地取消；外部未完成响应保持静默，处理规则不纳入本case。
    task body();
        wbb_sequencer sequencer;
        // 【防御性检查】测试必须取得所属sequencer和其配置。
        if (!$cast(sequencer, get_sequencer())) begin
            `fatal("WBB reset sequencer missing", "RESET_CONFIG")
        end
        cfg = sequencer.cfg;
        reset_reserved();
        refill_all(300);
        results.mark_stage("RESERVED_before_push");
        reset_pending();
        refill_all(400);
        results.mark_stage("PENDING_full_send_stalled");
        reset_issued();
        refill_all(600);
        results.mark_stage("ISSUED_external_response_silent");
        results.check_count("WBB local active reset pulses", pulses, 3);
        results.report("WBB_LOCAL_ACTIVE", pulses);
    endtask
endclass
