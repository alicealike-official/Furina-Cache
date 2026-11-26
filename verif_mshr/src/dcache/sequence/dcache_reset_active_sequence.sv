// CPU仍是唯一激励源；检查各本地非空状态清空，外部旧响应始终保持静默。
class dcache_reset_active_sequence extends dcache_reset_sequence;
    int reused_id;
    `uvm_object_utils(dcache_reset_active_sequence)
    function new(string name = "dcache_reset_active_sequence");
        super.new(name);
    endfunction
    // 普通场景没有外部在途；等响应场景只允许静默源，不执行迟到响应注入。
    task reset_local_state(bit no_external_pending = 1);
        longint edge_before;
        if (no_external_pending) begin
            results.check_count("DCache external reads complete before local reset", obs.reads, obs.read_acks);
            results.check_count("DCache external writes complete before local reset", obs.writes, obs.write_acks);
        end else begin
            results.check_condition(vif.memReadResp_valid === 1'b0 && vif.memWriteResp_valid === 1'b0,
                "Local in-flight reset requires silent external response sources");
        end
        clock_driver.assert_reset(1);
        pulses++;
        edge_before = clock_driver.rising_edges;
        check_empty();
        #(clock_driver.cfg.clock_period * 3.0);
        check_empty();
        results.check_count("DCache active reset has no clock edge", clock_driver.rising_edges, edge_before);
        clock_driver.release_reset();
    endtask
    // 复位后复用旧CPU ID发起新冷读，正常模型与CPU期望检查必须重新工作。
    task recover();
        cfg.read_request_enable = 1;
        cfg.write_request_enable = 1;
        cfg.read_response_enable = 1;
        cfg.write_response_enable = 1;
        cfg.cpu_read_ready = 1;
        cfg.cpu_write_ready = 1;
        next_id = reused_id;
        access(address(0, 5));
        obs.wait_empty();
    endtask
    // 填满读或写响应队列，再接受另一笔请求形成Stage2冻结；写队满时还保留旁路上下文。
    task reset_response_fifo(bit write_fifo);
        access(address(12, 1));
        cfg.cpu_read_ready = write_fifo;
        cfg.cpu_write_ready = !write_fifo;
        reused_id = next_id;
        for (int index = 0; index < 4; index++) begin
            access(address(12, 1), write_fifo, 32'h13570000+index, 0);
        end
        access(address(12, 1), !write_fifo, 32'h24680000, 0);
        obs.wait_cycles(3);
        results.check_condition(probe.s1Valid === 1'b1 && probe.s2Stuck === 1'b1,
            "FIFO reset missed frozen CPU request");
        if (write_fifo) begin
            results.check_condition(vif.cpuWriteResp_valid === 1'b1 && probe.p1Valid === 1'b1,
                "Write FIFO reset missed pending response and bypass context");
        end else begin
            results.check_condition(vif.cpuReadResp_valid === 1'b1, "Read FIFO reset missed pending response");
        end
        reset_local_state();
        recover();
    endtask
    // 脏淘汰预留沿后、push接受前复位，覆盖顶层待push寄存器和两IP本地义务。
    task reset_pending_push();
        dirty_set(0);
        cfg.read_request_enable = 0;
        cfg.write_request_enable = 0;
        reused_id = next_id;
        fork
            access(address(0, 6), 0, 0, 0);
            begin
                do @(vif.mon_cb); while (!(wbb_vif.mon_cb.reserve_en && wbb_vif.mon_cb.reserveOk));
                #(clock_driver.cfg.clock_period / 8.0);
                results.check_condition(wbb_vif.push_en === 1'b1, "Reset missed pending push after reservation");
                reset_local_state();
            end
        join
        recover();
    endtask
    // 四条脏淘汰均已push，分别阻塞内存写请求或写响应，覆盖PENDING与ISSUED状态。
    task reset_writeback(bit issued);
        dirty_set(0);
        cfg.write_request_enable = issued;
        cfg.write_response_enable = 0;
        reused_id = next_id;
        evict_set(0);
        obs.wait_cycles(8);
        results.check_condition(wbb_vif.full === 1'b1, "Writeback reset did not fill WBB");
        if (issued) begin
            results.check_count("Writeback issued pending acknowledgements", obs.writes-obs.write_acks, WBB_ENTRIES);
        end else begin
            results.check_condition(vif.memWriteReq_valid === 1'b1 && vif.memWriteReq_ready === 1'b0,
                "Pending WBB reset has no stalled send");
        end
        reset_local_state(!issued);
        recover();
    endtask
    // 冷行已有四个Slot，CPU读队列满后返回整行，形成已fill且replay被阻塞的状态。
    task reset_replay();
        access(address(12, 1));
        cfg.read_response_enable = 0;
        cfg.cpu_read_ready = 0;
        reused_id = next_id;
        for (int word_index = 0; word_index < 4; word_index++) access(address(13, 1, word_index), 0, 0, 0);
        for (int word_index = 0; word_index < 4; word_index++) access(address(12, 1, word_index), 0, 0, 0);
        obs.wait_cycles(4);
        cfg.read_response_enable = 1;
        do obs.wait_cycles(1); while (obs.reads != obs.read_acks || mshr_vif.replay_valid !== 1'b1);
        results.check_condition(mshr_vif.replay_ready === 1'b0 && mshr_vif.lockMask !== '0,
            "Replay reset missed locked entry stalled by response FIFO");
        reset_local_state();
        recover();
    endtask
    // 内存读已接受但返回暂停，仅检查本地等待状态清空，不把旧返回交给新ID。
    task reset_wait_response();
        cfg.read_response_enable = 0;
        reused_id = next_id;
        access(address(20, 77), 0, 0, 0);
        do obs.wait_cycles(1); while (obs.reads == obs.read_acks);
        results.check_condition(mshr_vif.lockMask !== '0, "Waiting reset has no locked miss");
        reset_local_state(0);
        recover();
    endtask
    // 分别命中FIFO、旁路、待push、WBB两阶段、replay与未命中等待，每次都验证重新可用。
    task body();
        cfg.continuous_cpu = 1;
        reset_response_fifo(1);
        results.mark_stage("WRITE_FIFO_pipeline_and_bypass_held");
        reset_response_fifo(0);
        results.mark_stage("READ_FIFO_pipeline_held");
        reset_pending_push();
        results.mark_stage("PUSH_pending_after_reservation");
        reset_writeback(0);
        results.mark_stage("WBB_PENDING_send_stalled");
        reset_replay();
        results.mark_stage("MSHR_REPLAY_response_FIFO_full");
        reset_wait_response();
        results.mark_stage("MSHR_WAIT_RESPONSE_external_source_silent");
        reset_writeback(1);
        results.mark_stage("WBB_ISSUED_external_source_silent");
        results.check_count("DCache local active reset pulses", pulses, 7);
        results.report("DCACHE_LOCAL_ACTIVE", pulses);
    endtask
endclass
