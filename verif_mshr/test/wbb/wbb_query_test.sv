class wbb_query_test extends wbb_base_test;
    `uvm_component_utils(wbb_query_test)

    function new(string name = "wbb_query_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual task run_sequence();
    extern function void check_query_coverage();
endclass

// 启动两轮查询场景，再通过base工具检查完整写回和最终数据。
task wbb_query_test::run_sequence();
    wbb_query_sequence seq;

    seq = wbb_query_sequence::type_id::create("seq");
    run_scenario(seq, 2 * WBB_ENTRIES);
    check_query_coverage();
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
