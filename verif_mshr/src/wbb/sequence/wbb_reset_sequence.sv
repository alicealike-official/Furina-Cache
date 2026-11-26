class wbb_reset_sequence extends wbb_base_sequence;
    clk_rst_driver clock_driver;
    virtual wbb_interface vif;
    wbb_activity_monitor obs;
    reset_checks results;
    int pulses;
    `uvm_object_utils(wbb_reset_sequence)
    function new(string name = "wbb_reset_sequence");
        super.new(name);
        results = reset_checks::type_id::create("results");
    endfunction
    // 直接观察公开输出，不等待下一有效沿，也不比较未定义的无效载荷和reserveSlot。
    function void check_empty();
        results.check_condition({vif.full, vif.reserveOk, vif.send_valid, vif.q0Same, vif.q1Same} === 5'b01000,
            "WBB reset did not establish the specified empty outputs");
    endfunction
    // 数据和查询地址由sequence创建；普通写回仍使用完整reserve/push事务。
    task transfer(int line_index);
        bit [LINE_WIDTH-1:0] line_data;
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            line_data[word_index*DATA_WIDTH +: DATA_WIDTH] = 32'h94100000 + line_index*32 + word_index;
        end
        writeback_line(ADDR_WIDTH'(line_index*BLOCK_SIZE), line_data,
            ADDR_WIDTH'(line_index*BLOCK_SIZE), ADDR_WIDTH'((line_index+1)*BLOCK_SIZE));
    endtask
    // 先确认无外部事务，再离沿断言；停钟期间检查输出和没有额外时钟沿。
    task idle_reset(bit stop_clock);
        longint edge_before;
        obs.wait_until_empty();
        clock_driver.assert_reset(stop_clock);
        pulses++;
        edge_before = clock_driver.rising_edges;
        check_empty();
        #(clock_driver.cfg.clock_period * 3.0);
        check_empty();
        if (stop_clock) results.check_count("WBB stopped clock edges", clock_driver.rising_edges, edge_before);
    endtask
    // 将请求对齐到释放后的第一或第二个有效沿，记录真实reserve握手，而非sequence调用时刻。
    task release_boundary(int gap_edges, int line_index);
        longint release_edge;
        longint accepted_edge;
        clock_driver.release_reset(1);
        release_edge = clock_driver.rising_edges;
        repeat (gap_edges) @(posedge vif.clk);
        fork
            transfer(line_index);
            begin
                do @(vif.mon_cb); while (!(vif.mon_cb.reserve_en && vif.mon_cb.reserveOk));
                accepted_edge = clock_driver.rising_edges;
            end
        join
        results.check_count("WBB release-to-reserve edges", accepted_edge-release_edge, gap_edges+1);
        obs.wait_until_empty();
    endtask
    // 重复空闲复位后重新使用全部槽位，检查容量没有损失且每笔写回正常完成。
    task body();
        check_empty();
        for (int round_index = 0; round_index < 4; round_index++) begin
            for (int index = 0; index < WBB_ENTRIES; index++) transfer(16*round_index+index+1);
            idle_reset(round_index / 2);
            release_boundary(round_index % 2, 16*round_index+8);
            results.mark_stage($sformatf("IDLE_clock_stopped_%0d_release_edge_%0d", round_index/2, round_index%2+1));
        end
        results.check_count("WBB reset pulses", pulses, 4);
        results.report("WBB", pulses);
    endtask
endclass
