// 验证SEND、等响应、待fill及待replay本地复位；旧响应不在复位后重新投递。
class mshr_reset_active_sequence extends mshr_reset_sequence;
    mshr_config cfg;
    `uvm_object_utils(mshr_reset_active_sequence)
    function new(string name = "mshr_reset_active_sequence");
        super.new(name);
    endfunction
    // 四个Entry分别属于不同set；接收控制决定它们停留在哪个可观察阶段。
    task occupy_all();
        for (int index = 0; index < MSHR_ENTRIES; index++) allocate(index);
        results.check_condition(vif.hasFree === 1'b0 && vif.lockMask !== '0,
            "Active reset did not occupy all MSHR entries");
    endtask
    // 外部无在途或保持响应静默时取消本地状态，不向新ID投递旧响应。
    task reset_local_state(bit no_external_pending = 1);
        longint edge_before;
        if (no_external_pending) begin
            results.check_count("MSHR external reads must already be complete", obs.in_flight.size(), 0);
        end else begin
            results.check_condition(vif.memReadResp_valid === 1'b0, "Local waiting reset requires a silent response source");
        end
        clock_driver.assert_reset(1);
        pulses++;
        edge_before = clock_driver.rising_edges;
        check_empty();
        #(clock_driver.cfg.clock_period * 3.0);
        check_empty();
        results.check_count("MSHR active reset has no clock edge", clock_driver.rising_edges, edge_before);
        clock_driver.release_reset();
    endtask
    // 复位后放行完整读写通路，复用旧CPU ID和Entry，检查新的生命周期正常完成。
    task recover();
        cfg.mem_request_enable = 1;
        cfg.mem_response_enable = 1;
        cfg.fill_enable = 1;
        cfg.replay_enable = 1;
        allocate(0);
        obs.wait_empty();
    endtask
    // SEND已呈现但内存不接受时，必须不依赖时钟清除读请求和锁。
    task reset_send();
        cfg.mem_request_enable = 0;
        occupy_all();
        obs.wait_cycles(2);
        results.check_condition(vif.memReadReq_valid === 1'b1, "SEND reset has no pending request");
        reset_local_state();
        recover();
    endtask
    // 内存响应均已返回，但fill接收被阻塞，复位取消挂起fill及全部Slot。
    task reset_fill();
        cfg.fill_enable = 0;
        cfg.replay_enable = 0;
        occupy_all();
        do obs.wait_cycles(1); while (obs.in_flight.size() != 0 || vif.fill_en !== 1'b1);
        results.check_condition(vif.fillReady === 1'b0, "Fill reset did not stall sink");
        reset_local_state();
        recover();
    endtask
    // 所有Entry已fill但replay被阻塞，复位清除待返回结果并释放所有way锁。
    task reset_replay();
        int target_fills;
        target_fills = obs.hits.exists("fill") ? obs.hits["fill"] + MSHR_ENTRIES : MSHR_ENTRIES;
        cfg.replay_enable = 0;
        occupy_all();
        do obs.wait_cycles(1); while (!obs.hits.exists("fill") || obs.hits["fill"] < target_fills);
        results.check_condition(vif.replay_valid === 1'b1 && vif.replay_ready === 1'b0,
            "Replay reset did not reach held valid response");
        reset_local_state();
        recover();
    endtask
    // 读已被内存接受但未返回时复位；只验本地清空，TB不把旧返回投递给复位后的Entry。
    task reset_wait_response();
        cfg.mem_response_enable = 0;
        occupy_all();
        do obs.wait_cycles(1); while (obs.in_flight.size() < MSHR_ENTRIES);
        results.check_count("MSHR waiting read count", obs.in_flight.size(), MSHR_ENTRIES);
        reset_local_state(0);
        recover();
    endtask
    // 四种本地非空状态各执行一次，之后均通过正常请求验证重新可用。
    task body();
        mshr_sequencer sequencer;
        // 【防御性检查】配置必须来自所属sequencer。
        if (!$cast(sequencer, get_sequencer())) begin
            `fatal("MSHR reset sequencer missing", "RESET_CONFIG")
        end
        cfg = sequencer.cfg;
        reset_send();
        results.mark_stage("SEND_request_stalled");
        reset_fill();
        results.mark_stage("FILL_sink_stalled");
        reset_replay();
        results.mark_stage("REPLAY_sink_stalled");
        reset_wait_response();
        results.mark_stage("WAIT_RESPONSE_external_source_silent");
        results.check_count("MSHR local active reset pulses", pulses, 4);
        results.report("MSHR_LOCAL_ACTIVE", pulses);
    endtask
endclass
