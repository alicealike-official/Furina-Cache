class mshr_reset_sequence extends mshr_base_sequence;
    clk_rst_driver clock_driver;
    virtual mshr_interface vif;
    mshr_activity_monitor obs;
    reset_checks results;
    int pulses;
    `uvm_object_utils(mshr_reset_sequence)
    function new(string name = "mshr_reset_sequence");
        super.new(name);
        results = reset_checks::type_id::create("results");
    endfunction
    // 空态包含查询、三条输出流及完整锁矩阵，不要求freeEntry或无效载荷为固定数值。
    function void check_empty();
        results.check_condition({vif.hasFree, vif.m0_hit, vif.m1_hit, vif.memReadReq_valid,
            vif.fill_en, vif.replay_valid} === 6'b100000, "MSHR reset outputs are not empty");
        results.check_condition(vif.lockMask === '0, "MSHR reset did not clear all way locks");
    endfunction
    // 每笔请求采用新set，复位后可重复使用CPU ID；正常提交仍由driver选择真实空Entry。
    task allocate(int index, bit fast_release = 0);
        mshr_transaction item;
        item = mshr_transaction::type_id::create("allocate");
        item.operation = MSHR_ALLOC;
        item.tag = TAG_WIDTH'(1);
        item.index = INDEX_WIDTH'(index);
        item.way = WAY_WIDTH'(0);
        item.wordOff = WORD_OFF_WIDTH'(index % WORDS_PER_BLOCK);
        item.respId = CPU_ID_WIDTH'(index);
        item.isWrite = index % 2;
        item.wData = DATA_WIDTH'(32'h65200000 + index);
        item.q0Tag = item.tag;
        item.q1Tag = item.tag;
        item.q0Index = item.index;
        item.q1Index = item.index;
        item.reset_release_alloc = fast_release;
        step(item);
    endtask
    // 空闲重复复位采用同一时钟复位driver，断言后在下一有效沿前直接检查。
    task idle_reset(bit stop_clock);
        longint edge_before;
        obs.wait_empty();
        clock_driver.assert_reset(stop_clock);
        pulses++;
        edge_before = clock_driver.rising_edges;
        check_empty();
        #(clock_driver.cfg.clock_period * 3.0);
        check_empty();
        if (stop_clock) results.check_count("MSHR stopped clock edges", clock_driver.rising_edges, edge_before);
    endtask
    // 复位后已知空态允许直接准备alloc，覆盖第一/第二有效沿并记录真实提交时刻。
    task release_boundary(int gap_edges);
        longint release_edge;
        longint accepted_edge;
        clock_driver.release_reset(1);
        release_edge = clock_driver.rising_edges;
        repeat (gap_edges) @(posedge vif.clk);
        fork
            allocate((pulses-1)/2, 1);
            begin
                do @(vif.mon_cb); while (!vif.mon_cb.alloc_en);
                accepted_edge = clock_driver.rising_edges;
            end
        join
        results.check_count("MSHR release-to-alloc edges", accepted_edge-release_edge, gap_edges+1);
        obs.wait_empty();
    endtask
    // 各轮先完成读写生命周期，再重复复位；重新分配四个Entry确认可用容量不减少。
    task body();
        check_empty();
        for (int round_index = 0; round_index < 4; round_index++) begin
            for (int index = 0; index < MSHR_ENTRIES; index++) allocate(index);
            idle_reset(round_index / 2);
            release_boundary(round_index % 2);
            results.mark_stage($sformatf("IDLE_clock_stopped_%0d_release_edge_%0d", round_index/2, round_index%2+1));
        end
        results.check_count("MSHR reset pulses", pulses, 4);
        results.report("MSHR", pulses);
    endtask
endclass
