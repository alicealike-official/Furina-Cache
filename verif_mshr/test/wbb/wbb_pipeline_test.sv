// 检查严格下一拍push的流水输入，不放宽为延迟push模式。
// sequence安排四个批次；test逐笔检查实际输入归属，并使用base工具核对计数和最终内存。
class wbb_pipeline_test extends wbb_base_test;
    typedef wbb_activity_monitor::activity_snapshot_t activity_snapshot_t;
    typedef wbb_scenario_sequence::writeback_record_t writeback_record_t;

    `uvm_component_utils(wbb_pipeline_test)

    function new(string name = "wbb_pipeline_test", uvm_component parent = null);
        super.new(name, parent);
        fixed_input_mode = WBB_INPUT_PIPELINE;
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern function void check_batch(wbb_pipeline_sequence seq, int stage, int count,
        int first_record, bit continuous);
    extern function void check_entry(wbb_pipeline_sequence seq, int stage, int index,
        int count, int first_record);
    extern function void check_input_queries(wbb_pipeline_sequence seq, wbb_sample sample,
        int first_record, int count, int fallback_record, string label);
    extern function void check_stall_recovery(wbb_pipeline_sequence seq);
    extern function void check_idle_gap(wbb_pipeline_sequence seq, int index);
endclass

function void wbb_pipeline_test::build_phase(uvm_phase phase);
    int reserve_budget;
    int total_budget;

    super.build_phase(phase);
`ifdef WBB_ALLOW_DELAYED_PUSH
    `fatal("wbb_pipeline_test requires the strict next-cycle-push build", "WBB_PIPELINE_CONFIG")
`endif
    if (WBB_ENTRIES < 2) begin
        `fatal("Pipeline overlap requires at least two WBB entries", "WBB_PIPELINE_CONFIG")
    end
    cfg.allow_delayed_push = 0;
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 2;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
    reserve_budget = 4 * WBB_ENTRIES + wbb_pipeline_sequence::MIN_STALL_CYCLES + 16;
    total_budget = clk_cfg.initial_reset_cycles + 12 * wbb_pipeline_sequence::WRITEBACK_COUNT +
        4 * wbb_pipeline_sequence::MIN_STALL_CYCLES + 2 * wbb_pipeline_sequence::GAP_CYCLES + 100;
    if (cfg.reserve_timeout_cycles < reserve_budget) begin
        cfg.reserve_timeout_cycles = reserve_budget;
    end
    if (cfg.timeout_cycles < total_budget) begin
        cfg.timeout_cycles = total_budget;
    end
endfunction

// 执行三个场景，再逐批检查实际拍数、输入数据归属和必要的重叠事件。
// run_scenario沿用C++模型、SVA和最终内存回读；这里的输入比较用于发现driver串错事务的DV问题。
task wbb_pipeline_test::run_sequence();
    wbb_pipeline_sequence seq;

    seq = wbb_pipeline_sequence::type_id::create("seq");
    run_scenario(seq, wbb_pipeline_sequence::WRITEBACK_COUNT);
    check_batch(seq, 0, WBB_ENTRIES, 0, 1);
    check_batch(seq, 1, WBB_ENTRIES + 2, WBB_ENTRIES, 0);
    check_stall_recovery(seq);
    check_idle_gap(seq, 0);
    check_batch(seq, 2, 1, 2 * WBB_ENTRIES + 2, 1);
    check_idle_gap(seq, 1);
    check_batch(seq, 3, 2, 2 * WBB_ENTRIES + 3, 1);
    check_count("pipeline delayed pushes", env.activity.delayed_push_count, 0);
endtask

// 按批次起止计数检查完整写回；连续批次还要求reserve和push各连续count拍，重叠count-1次。
// 每批最后一笔只有push、没有新的reserve，必须被保留而不能在item结束时丢掉。
function void wbb_pipeline_test::check_batch(wbb_pipeline_sequence seq, int stage, int count,
    int first_record, bit continuous);
    activity_snapshot_t first;
    activity_snapshot_t last;

    first = seq.starts[stage];
    last = seq.ends[stage];
    check_count($sformatf("batch %0d reserve", stage), last.reserve_count - first.reserve_count, count);
    check_count($sformatf("batch %0d push", stage), last.push_count - first.push_count, count);
    check_count($sformatf("batch %0d send", stage), last.send_count - first.send_count, count);
    check_count($sformatf("batch %0d response", stage), last.response_count - first.response_count, count);
    check_count($sformatf("batch %0d tail push", stage), last.tail_push_count - first.tail_push_count, 1);
    if (continuous) begin
        check_count($sformatf("batch %0d overlap", stage), last.overlap_count - first.overlap_count, count - 1);
    end
    if (env.activity.reserve_cycles.size() < first.reserve_count + count ||
        env.activity.push_cycles.size() < first.push_count + count ||
        env.activity.reserve_samples.size() < first.reserve_count + count ||
        env.activity.push_samples.size() < first.push_count + count ||
        seq.get_record_count() < first_record + count) begin
        `error($sformatf("Batch %0d has incomplete pipeline records", stage), "WBB_PIPELINE_RECORDS")
        return;
    end
    for (int index = 0; index < count; index++) begin
        check_entry(seq, stage, index, count, first_record);
        if (continuous && index > 0) begin
            check_count($sformatf("batch %0d consecutive reserve", stage),
                int'(env.activity.reserve_cycles[first.reserve_count + index] -
                    env.activity.reserve_cycles[first.reserve_count + index - 1]), 1);
            check_count($sformatf("batch %0d consecutive push", stage),
                int'(env.activity.push_cycles[first.push_count + index] -
                    env.activity.push_cycles[first.push_count + index - 1]), 1);
        end
    end
    `info($sformatf("stage=%0d entries=%0d reserve=%0d push=%0d send=%0d response=%0d overlap=%0d tail_push=%0d",
        stage, count, last.reserve_count - first.reserve_count, last.push_count - first.push_count,
        last.send_count - first.send_count, last.response_count - first.response_count,
        last.overlap_count - first.overlap_count, last.tail_push_count - first.tail_push_count), "WBB_PIPELINE_COVERAGE")
endfunction

// 逐笔确认push严格晚于成功reserve一拍，使用当时返回的槽号，并携带sequence原先准备的数据。
// 查询口在reserve与push重叠时只能有一对值，单独调用查询来源检查，包含reserve失败的那拍。
function void wbb_pipeline_test::check_entry(wbb_pipeline_sequence seq, int stage, int index,
    int count, int first_record);
    wbb_sample reservation;
    wbb_sample pushed;
    writeback_record_t record;
    int reserve_index;
    int push_index;

    reserve_index = seq.starts[stage].reserve_count + index;
    push_index = seq.starts[stage].push_count + index;
    reservation = env.activity.reserve_samples[reserve_index];
    pushed = env.activity.push_samples[push_index];
    record = seq.get_record(first_record + index);
    if (reservation == null || pushed == null) begin
        `error("Pipeline input sample is null", "WBB_PIPELINE_RECORDS")
        return;
    end
    check_count($sformatf("batch %0d item %0d reserve-to-push", stage, index),
        int'(env.activity.push_cycles[push_index] - env.activity.reserve_cycles[reserve_index]), 1);
    if (reservation.reserve_addr !== record.addr || pushed.push_slot !== reservation.reserveSlot ||
        pushed.push_line !== record.line_data) begin
        `error($sformatf("Batch %0d item %0d input address/slot/data differs from its original transaction",
            stage, index), "WBB_PIPELINE_STIMULUS")
    end
    check_input_queries(seq, reservation, first_record, count, first_record + index, "reserve");
    check_input_queries(seq, pushed, first_record, count, first_record + index, "push");
    if (index == count - 1 && pushed.reserve_en !== 1'b0) begin
        `error($sformatf("Batch %0d tail push must not start another reserve", stage), "WBB_PIPELINE_TAIL")
    end
endfunction

// reserve_en为1时，按实际正在申请的地址查找查询来源，即使本拍reserve失败也一样。
// 没有reserve时使用尾部push的查询对：q0为本批上一条地址，首项为0；q1为该条自身地址。
function void wbb_pipeline_test::check_input_queries(wbb_pipeline_sequence seq, wbb_sample sample,
    int first_record, int count, int fallback_record, string label);
    writeback_record_t source;
    writeback_record_t previous;
    bit [ADDR_WIDTH-1:0] expected_q0;
    int source_record;

    source_record = -1;
    if (sample.reserve_en === 1'b1) begin
        for (int index = 0; index < count; index++) begin
            source = seq.get_record(first_record + index);
            if (source.addr == sample.reserve_addr) begin
                source_record = first_record + index;
                break;
            end
        end
    end else if (sample.reserve_en === 1'b0) begin
        source_record = fallback_record;
    end
    if (source_record < first_record || source_record >= first_record + count) begin
        `error($sformatf("%s query source is not a transaction in this pipeline batch", label), "WBB_PIPELINE_QUERY")
        return;
    end
    source = seq.get_record(source_record);
    expected_q0 = '0;
    if (source_record > first_record) begin
        previous = seq.get_record(source_record - 1);
        expected_q0 = previous.addr;
    end
    if (sample.q0Addr !== expected_q0 || sample.q1Addr !== source.addr) begin
        `error($sformatf("%s queries expected=(0x%h,0x%h) actual=(0x%h,0x%h)",
            label, expected_q0, source.addr, sample.q0Addr, sample.q1Addr), "WBB_PIPELINE_QUERY")
    end
endfunction

// 检查第二批确实满槽等待：旧push继续发生，首个响应当拍不提前预留，下一拍恢复且再次产生重叠。
function void wbb_pipeline_test::check_stall_recovery(wbb_pipeline_sequence seq);
    activity_snapshot_t first;
    activity_snapshot_t last;

    first = seq.starts[1];
    last = seq.ends[1];
    check_count("pipeline push while reserve is blocked", last.blocked_push_cycles - first.blocked_push_cycles, 1, 1);
    check_count("pipeline blocked reserve cycles", last.blocked_reserve_cycles - first.blocked_reserve_cycles,
        wbb_pipeline_sequence::MIN_STALL_CYCLES, 1);
    check_count("pipeline full response still blocks reserve",
        last.full_response_block_count - first.full_response_block_count, 1, 1);
    check_count("pipeline reserve recovers on next edge",
        last.full_response_recovery_count - first.full_response_recovery_count, 1, 1);
    check_count("pipeline overlap after recovery", last.resumed_overlap_count - first.resumed_overlap_count, 1, 1);
    `info($sformatf("stage=1 blocked_push=%0d blocked_reserve=%0d full_response_block=%0d next_edge_recovery=%0d resumed_overlap=%0d",
        last.blocked_push_cycles - first.blocked_push_cycles,
        last.blocked_reserve_cycles - first.blocked_reserve_cycles,
        last.full_response_block_count - first.full_response_block_count,
        last.full_response_recovery_count - first.full_response_recovery_count,
        last.resumed_overlap_count - first.resumed_overlap_count), "WBB_PIPELINE_COVERAGE")
endfunction

// 两批之间已经没有待完成写回，空闲段内不应出现任何新的reserve、push、send或响应。
function void wbb_pipeline_test::check_idle_gap(wbb_pipeline_sequence seq, int index);
    activity_snapshot_t first;
    activity_snapshot_t last;

    first = seq.idle_starts[index];
    last = seq.idle_ends[index];
    check_count($sformatf("idle gap %0d reserve", index), last.reserve_count - first.reserve_count, 0);
    check_count($sformatf("idle gap %0d push", index), last.push_count - first.push_count, 0);
    check_count($sformatf("idle gap %0d send", index), last.send_count - first.send_count, 0);
    check_count($sformatf("idle gap %0d response", index), last.response_count - first.response_count, 0);
    check_count($sformatf("idle gap %0d sampled cycles", index), int'(last.cycle - first.cycle),
        wbb_pipeline_sequence::GAP_CYCLES, 1);
    `info($sformatf("idle_gap=%0d cycles=%0d reserve=0 push=0 send=0 response=0",
        index, last.cycle - first.cycle), "WBB_PIPELINE_COVERAGE")
endfunction
