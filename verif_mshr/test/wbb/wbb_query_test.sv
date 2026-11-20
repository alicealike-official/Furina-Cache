class wbb_query_test extends wbb_base_test;
    `uvm_component_utils(wbb_query_test)

    function new(string name = "wbb_query_test", uvm_component parent = null);
        super.new(name, parent);
        supports_input_modes = 1;
    endfunction

    extern virtual task run_sequence();
    extern function void check_query_coverage();
    extern function void check_overlap_queries();
endclass

// 启动两轮查询场景，再通过base工具检查完整写回和最终数据。
task wbb_query_test::run_sequence();
    wbb_query_sequence query_seq;

    query_seq = wbb_query_sequence::type_id::create("seq");
    run_scenario(query_seq, 2 * WBB_ENTRIES);

    check_query_coverage();
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        check_overlap_queries();
    end
endtask

// 查询口没有enable，每拍都有效；检查reserved、pending、issued以及非空时双不命中均实际出现。
function void wbb_query_test::check_query_coverage();
    // 阶段1为reserved：确认两口命中及各自单独命中的组合都出现过。
    check_count("reserved both queries", env.activity.query_matrix[1][1], 1, 1);
    check_count("reserved q0 only", env.activity.query_matrix[1][0], 1, 1);
    check_count("reserved q1 only", env.activity.query_matrix[0][1], 1, 1);

    // 阶段2为pending，阶段3为issued；两个阶段都要覆盖双命中与单口命中。
    for (int stage = 2; stage <= 3; stage++) begin
        check_count($sformatf("stage %0d both hits", stage), env.activity.query_matrix[stage][stage], 1, 1);
        check_count($sformatf("stage %0d q0 hit", stage), env.activity.query_matrix[stage][0], 1, 1);
        check_count($sformatf("stage %0d q1 hit", stage), env.activity.query_matrix[0][stage], 1, 1);
    end

    // 补查地址关系和释放边界：同址、异址、仍有占用时双miss，以及排空后的查询。
    check_count("same-address dual hit", env.activity.same_hit_cycles, 1, 1);
    check_count("different-address dual hit", env.activity.different_hit_cycles, 1, 1);
    check_count("both miss while occupied", env.activity.query_none_while_occupied, 1, 1);
    check_count("queries after all responses", env.activity.empty_query_cycles, 6, 1);

    `info($sformatf("same_hits=%0d different_hits=%0d occupied_misses=%0d empty_queries=%0d",
        env.activity.same_hit_cycles, env.activity.different_hit_cycles,
        env.activity.query_none_while_occupied, env.activity.empty_query_cycles), "WBB_QUERY_COVERAGE")
endfunction

// 只看成功reserve与旧push同拍的真实采样，确认reserved查询组合确实发生在流水重叠期间。
// 上一笔成功reserve的地址对应本拍push；批次后单独执行的query不能增加这些计数。
function void wbb_query_test::check_overlap_queries();
    wbb_sample overlap_sample;
    wbb_sample prior_reserve;
    int reserved_dual_hits;
    int reserved_q0_hits;
    int reserved_q1_hits;
    int distinct_dual_hits;

    // 这些计数只统计真实reserve/push重叠拍，独立query操作不能补足它们。
    reserved_dual_hits = 0;
    reserved_q0_hits = 0;
    reserved_q1_hits = 0;
    distinct_dual_hits = 0;

    for (int sample_index = 0; sample_index < env.activity.reserve_samples.size(); sample_index++) begin
        // 从成功reserve的记录中，挑出同时有旧push的采样。
        overlap_sample = env.activity.reserve_samples[sample_index];
        if (overlap_sample.push_en !== 1'b1) begin
            continue;
        end

        // 找到上一笔预留，确认本拍push的确使用它保存的槽号。
        if (sample_index == 0) begin
            `error("Pipeline query overlap has no earlier reservation", "WBB_QUERY_PIPELINE")
            continue;
        end
        prior_reserve = env.activity.reserve_samples[sample_index - 1];
        if (overlap_sample.push_slot !== prior_reserve.reserveSlot) begin
            `error("Pipeline query sample does not push the previous reservation", "WBB_QUERY_PIPELINE")
        end

        // 沿前旧地址仍为reserved，分别统计两口同时命中和单口命中。
        if (overlap_sample.q0Addr == prior_reserve.reserve_addr &&
            overlap_sample.q1Addr == prior_reserve.reserve_addr &&
            overlap_sample.q0Same === 1'b1 && overlap_sample.q1Same === 1'b1) begin
            reserved_dual_hits++;
        end
        if (overlap_sample.q0Addr == prior_reserve.reserve_addr &&
            overlap_sample.q0Same === 1'b1 && overlap_sample.q1Same === 1'b0) begin
            reserved_q0_hits++;
        end
        if (overlap_sample.q1Addr == prior_reserve.reserve_addr &&
            overlap_sample.q1Same === 1'b1 && overlap_sample.q0Same === 1'b0) begin
            reserved_q1_hits++;
        end

        // 两口命中不同地址时，至少一个必须是本拍正在push的旧预留地址。
        if (overlap_sample.q0Addr != overlap_sample.q1Addr &&
            overlap_sample.q0Same === 1'b1 && overlap_sample.q1Same === 1'b1 &&
            (overlap_sample.q0Addr == prior_reserve.reserve_addr || overlap_sample.q1Addr == prior_reserve.reserve_addr)) begin
            distinct_dual_hits++;
        end
    end

    // 每种重叠查询组合至少命中一次，再输出实际计数供回归记录。
    check_count("pipeline overlap reserved both queries", reserved_dual_hits, 1, 1);
    check_count("pipeline overlap reserved q0 only", reserved_q0_hits, 1, 1);
    check_count("pipeline overlap reserved q1 only", reserved_q1_hits, 1, 1);
    check_count("pipeline overlap different occupied addresses", distinct_dual_hits, 1, 1);
    `info($sformatf("reserved_both=%0d reserved_q0_only=%0d reserved_q1_only=%0d different_hits=%0d",
        reserved_dual_hits, reserved_q0_hits, reserved_q1_hits, distinct_dual_hits), "WBB_QUERY_PIPELINE_COVERAGE")
endfunction
