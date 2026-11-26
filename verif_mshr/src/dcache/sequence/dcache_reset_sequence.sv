class dcache_reset_sequence extends dcache_scenario_sequence;
    clk_rst_driver clock_driver;
    virtual dcache_interface vif;
    virtual dcache_probe_interface probe;
    virtual mshr_interface mshr_vif;
    virtual wbb_interface wbb_vif;
    reset_checks results;
    int pulses;
    `uvm_object_utils(dcache_reset_sequence)
    function new(string name = "dcache_reset_sequence");
        super.new(name);
        results = reset_checks::type_id::create("results");
    endfunction
    // 只检查控制/有效状态，tag和data无效时不要求清零；FIFO只检查DCache可见输出。
    function void check_empty();
        bit [255:0] expected_order;
        for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
            for (int way = 0; way < NUM_WAYS; way++) expected_order[set_index*8+way*2 +: 2] = 2'(way);
        end
        results.check_condition({vif.cpuReadResp_valid, vif.cpuWriteResp_valid,
            vif.memReadReq_valid, vif.memWriteReq_valid} === 4'b0000, "DCache reset left valid output traffic");
        results.check_condition({probe.s1Valid, probe.p1Valid, wbb_vif.push_en} === 3'b000,
            "DCache reset left pipeline, bypass or pending push valid");
        results.check_condition(probe.cache_valid_map === '0, "DCache reset did not clear every Cache valid bit");
        results.check_condition(probe.cache_dirty_map === '0, "DCache reset did not clear every Cache dirty bit");
        results.check_condition(probe.fifo_order === expected_order, "DCache FIFO policy initial order is wrong");
        results.check_condition(mshr_vif.lockMask === '0 && mshr_vif.hasFree === 1'b1 &&
            mshr_vif.fill_en === 1'b0 && mshr_vif.replay_valid === 1'b0, "DCache MSHR reset state is wrong");
        results.check_condition(wbb_vif.full === 1'b0 && wbb_vif.reserveOk === 1'b1 &&
            wbb_vif.send_valid === 1'b0, "DCache WBB reset state is wrong");
    endfunction
    // 使全部set/way有效且脏，再在每个set额外填入一行，令FIFO顺序确实偏离初值。
    task warm_state();
        for (int set_index = 0; set_index < NUM_SETS; set_index++) begin
            for (int tag = 1; tag <= NUM_WAYS+1; tag++) begin
                access(address(set_index, tag), 1, 32'h81200000+set_index*256+tag);
            end
        end
        obs.wait_empty();
        results.check_condition((&probe.cache_valid_map) === 1'b1, "Reset precondition missed valid lines");
        results.check_condition((&probe.cache_dirty_map) === 1'b1, "Reset precondition missed dirty lines");
        results.check_condition(probe.fifo_order[7:0] !== 8'he4, "Reset precondition did not change FIFO order");
    endtask
    // 事务排空后离沿复位，停钟时证明输出清空发生在没有新有效沿的情况下。
    task idle_reset(bit stop_clock);
        longint edge_before;
        obs.wait_empty();
        clock_driver.assert_reset(stop_clock);
        pulses++;
        edge_before = clock_driver.rising_edges;
        check_empty();
        #(clock_driver.cfg.clock_period * 3.0);
        check_empty();
        if (stop_clock) results.check_count("DCache stopped clock edges", clock_driver.rising_edges, edge_before);
    endtask
    // 第一/第二有效沿接受冷读；数据期望由实际后端重新建立，旧Cache脏内容不能当作命中。
    task release_boundary(int gap_edges);
        longint release_edge;
        int read_before;
        clock_driver.release_reset(1);
        release_edge = clock_driver.rising_edges;
        read_before = obs.reads;
        repeat (gap_edges) @(posedge vif.clk);
        access(address(0, 2), 0, 0, 0);
        results.check_count("DCache release-to-request edges", clock_driver.rising_edges-release_edge, gap_edges+1);
        obs.wait_empty();
        results.check_count("DCache first request must refetch invalidated line", obs.reads-read_before, 1);
    endtask
    // 先检查启动空态，再验证非空存储复位、重复空闲复位和两个释放边界。
    task body();
        cfg.continuous_cpu = 1;
        check_empty();
        warm_state();
        for (int round_index = 0; round_index < 4; round_index++) begin
            idle_reset(round_index / 2);
            release_boundary(round_index % 2);
            results.mark_stage($sformatf("IDLE_clock_stopped_%0d_release_edge_%0d", round_index/2, round_index%2+1));
        end
        results.check_count("DCache reset pulses", pulses, 4);
        results.report("DCache", pulses);
    endtask
endclass
