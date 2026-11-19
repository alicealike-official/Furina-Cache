// 检查按实际已发送ID逆序返回响应时，只释放对应槽，其余地址继续被查询到。
class wbb_response_order_test extends wbb_base_test;
    `uvm_component_utils(wbb_response_order_test)

    function new(string name = "wbb_response_order_test",
        uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern function void check_response_order(wbb_response_order_sequence seq);
endclass

function void wbb_response_order_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 2;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
endfunction

// 运行逆序响应和逐次查询，核对实际顺序并确认释放后未命中、未释放地址仍命中的场景发生。
task wbb_response_order_test::run_sequence();
    wbb_response_order_sequence seq;

    seq = wbb_response_order_sequence::type_id::create("seq");
    run_scenario(seq, wbb_response_order_sequence::WRITEBACK_COUNT);
    check_response_order(seq);
    check_count("out-of-order response events", env.activity.response_reorders, WBB_ENTRIES - 1, 1);
    check_count("released address and surviving issued address queried", env.activity.query_matrix[0][3], WBB_ENTRIES - 1, 1);
    check_count("queries after final release", env.activity.empty_query_cycles, 1, 1);
    `info($sformatf("responses=%0d reordered=%0d released_vs_issued_queries=%0d",
        env.activity.response_count, env.activity.response_reorders,
        env.activity.query_matrix[0][3]), "WBB_RESPONSE_ORDER_COVERAGE")
endtask

// 逐项比较实际响应ID与sequence从发送记录生成的逆序列表，避免只有配置打开却没有真正乱序。
function void wbb_response_order_test::check_response_order(wbb_response_order_sequence seq);
    if (seq.expected_ids.size() != WBB_ENTRIES ||
        env.activity.response_ids.size() < seq.response_start + WBB_ENTRIES) begin
        `error("Response order records are incomplete", "WBB_RESPONSE_ORDER_RECORDS")
        return;
    end
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        check_count($sformatf("response position %0d", index),
            env.activity.response_ids[seq.response_start + index], seq.expected_ids[index]);
    end
endfunction
