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
    wbb_query_sequence seq;

    seq = wbb_query_sequence::type_id::create("seq");
    run_scenario(seq, 2 * WBB_ENTRIES);
    check_query_coverage();
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        check_overlap_queries();
    end
endtask

// 查询口没有enable，每拍都有效；检查reserved、pending、issued以及非空时双不命中均实际出现。
function void wbb_query_test::check_query_coverage();
    check_count("reserved both queries", env.activity.query_matrix[1][1], 1, 1);
    check_count("reserved q0 only", env.activity.query_matrix[1][0], 1, 1);
    check_count("reserved q1 only", env.activity.query_matrix[0][1], 1, 1);
    for (int stage = 2; stage <= 3; stage++) begin
        check_count($sformatf("stage %0d both hits", stage), env.activity.query_matrix[stage][stage], 1, 1);
        check_count($sformatf("stage %0d q0 hit", stage), env.activity.query_matrix[stage][0], 1, 1);
        check_count($sformatf("stage %0d q1 hit", stage), env.activity.query_matrix[0][stage], 1, 1);
    end
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
    wbb_sample current;
    wbb_sample previous;
    int both_reserved;
    int left_reserved;
    int right_reserved;
    int different_hits;

    both_reserved = 0;
    left_reserved = 0;
    right_reserved = 0;
    different_hits = 0;
    for (int index = 0; index < env.activity.reserve_samples.size(); index++) begin
        current = env.activity.reserve_samples[index];
        if (current.push_en !== 1'b1) begin
            continue;
        end
        if (index == 0) begin
            `error("Pipeline query overlap has no earlier reservation", "WBB_QUERY_PIPELINE")
            continue;
        end
        previous = env.activity.reserve_samples[index - 1];
        if (current.push_slot !== previous.reserveSlot) begin
            `error("Pipeline query sample does not push the previous reservation", "WBB_QUERY_PIPELINE")
        end
        if (current.q0Addr == previous.reserve_addr && current.q1Addr == previous.reserve_addr &&
            current.q0Same === 1'b1 && current.q1Same === 1'b1) begin
            both_reserved++;
        end
        if (current.q0Addr == previous.reserve_addr && current.q0Same === 1'b1 && current.q1Same === 1'b0) begin
            left_reserved++;
        end
        if (current.q1Addr == previous.reserve_addr && current.q1Same === 1'b1 && current.q0Same === 1'b0) begin
            right_reserved++;
        end
        if (current.q0Addr != current.q1Addr && current.q0Same === 1'b1 && current.q1Same === 1'b1 &&
            (current.q0Addr == previous.reserve_addr || current.q1Addr == previous.reserve_addr)) begin
            different_hits++;
        end
    end
    check_count("pipeline overlap reserved both queries", both_reserved, 1, 1);
    check_count("pipeline overlap reserved q0 only", left_reserved, 1, 1);
    check_count("pipeline overlap reserved q1 only", right_reserved, 1, 1);
    check_count("pipeline overlap different occupied addresses", different_hits, 1, 1);
    `info($sformatf("reserved_both=%0d reserved_q0_only=%0d reserved_q1_only=%0d different_hits=%0d",
        both_reserved, left_reserved, right_reserved, different_hits), "WBB_QUERY_PIPELINE_COVERAGE")
endfunction
