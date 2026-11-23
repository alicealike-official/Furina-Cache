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
    // 【防御性检查】核对编译模式是否支持本操作，避免环境模式与协议检查配置不一致。
`ifdef WBB_ALLOW_DELAYED_PUSH
    `fatal("wbb_pipeline_test requires the strict next-cycle-push build", "WBB_PIPELINE_CONFIG")
`endif
    // 【防御性检查】确认当前容量足以构造本场景，不代表DUT功能结果检查。
    if (WBB_ENTRIES < 2) begin
        `fatal("Pipeline overlap requires at least two WBB entries", "WBB_PIPELINE_CONFIG")
    end

    // 固定严格push与可控的内存策略，不能用延迟模式放宽流水要求。
    cfg.allow_delayed_push = 0;
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 2;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;

    // 按事务数量和等待拍数估算超时预算，保持与时钟周期无关。
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

// 执行四个批次，逐批检查实际拍数、输入数据归属，以及连续、停顿恢复和尾部重叠。
// run_scenario沿用C++模型、SVA和最终内存回读；这里的输入比较用于发现driver串错事务的DV问题。
task wbb_pipeline_test::run_sequence();
    wbb_pipeline_sequence seq;

    seq = wbb_pipeline_sequence::type_id::create("seq");
    run_scenario(seq, wbb_pipeline_sequence::WRITEBACK_COUNT);

    // 依次检查连续批次、满槽恢复，以及空闲后的单笔和短批次。
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
    activity_snapshot_t start_counts;
    activity_snapshot_t end_counts;

    // 取本批起止快照，核对各类事件差值及尾部push数量。
    start_counts = seq.starts[stage];
    end_counts = seq.ends[stage];
    check_count($sformatf("batch %0d reserve", stage), end_counts.reserve_count - start_counts.reserve_count, count);
    check_count($sformatf("batch %0d push", stage), end_counts.push_count - start_counts.push_count, count);
    check_count($sformatf("batch %0d send", stage), end_counts.send_count - start_counts.send_count, count);
    check_count($sformatf("batch %0d response", stage), end_counts.response_count - start_counts.response_count, count);
    check_count($sformatf("batch %0d tail push", stage), end_counts.tail_push_count - start_counts.tail_push_count, 1);
    if (continuous) begin
        check_count($sformatf("batch %0d overlap", stage), end_counts.overlap_count - start_counts.overlap_count, count - 1);
    end

    // 检查全部记录可用，避免对不完整的采样队列继续索引。
    if (env.activity.reserve_cycles.size() < start_counts.reserve_count + count ||
        env.activity.push_cycles.size() < start_counts.push_count + count ||
        env.activity.reserve_samples.size() < start_counts.reserve_count + count ||
        env.activity.push_samples.size() < start_counts.push_count + count ||
        seq.get_record_count() < first_record + count) begin
        `error($sformatf("Batch %0d has incomplete pipeline records", stage), "WBB_PIPELINE_RECORDS")
        return;
    end

    // 逐笔检查事务归属；无阻塞批次还检查相邻reserve/push连续发生。
    for (int index = 0; index < count; index++) begin
        check_entry(seq, stage, index, count, first_record);
        if (continuous && index > 0) begin
            check_count($sformatf("batch %0d consecutive reserve", stage),
                int'(env.activity.reserve_cycles[start_counts.reserve_count + index] -
                    env.activity.reserve_cycles[start_counts.reserve_count + index - 1]), 1);
            check_count($sformatf("batch %0d consecutive push", stage),
                int'(env.activity.push_cycles[start_counts.push_count + index] -
                    env.activity.push_cycles[start_counts.push_count + index - 1]), 1);
        end
    end
    `info($sformatf("stage=%0d entries=%0d reserve=%0d push=%0d send=%0d response=%0d overlap=%0d tail_push=%0d",
        stage, count, end_counts.reserve_count - start_counts.reserve_count, end_counts.push_count - start_counts.push_count,
        end_counts.send_count - start_counts.send_count, end_counts.response_count - start_counts.response_count,
        end_counts.overlap_count - start_counts.overlap_count, end_counts.tail_push_count - start_counts.tail_push_count), "WBB_PIPELINE_COVERAGE")
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

    // 按批次起点定位该笔reserve、push和原始激励。
    reserve_index = seq.starts[stage].reserve_count + index;
    push_index = seq.starts[stage].push_count + index;
    reservation = env.activity.reserve_samples[reserve_index];
    pushed = env.activity.push_samples[push_index];
    record = seq.get_record(first_record + index);
    if (reservation == null || pushed == null) begin
        `error("Pipeline input sample is null", "WBB_PIPELINE_RECORDS")
        return;
    end

    // 先核对push时序，再核对原地址、预留槽和整行数据。
    check_count($sformatf("batch %0d item %0d reserve-to-push", stage, index),
        int'(env.activity.push_cycles[push_index] - env.activity.reserve_cycles[reserve_index]), 1);
    if (reservation.reserve_addr !== record.addr || pushed.push_slot !== reservation.reserveSlot ||
        pushed.push_line !== record.line_data) begin
        `error($sformatf("Batch %0d item %0d input address/slot/data differs from its original transaction",
            stage, index), "WBB_PIPELINE_STIMULUS")
    end

    // 最后核对两个采样时刻的查询来源，以及尾push不会携带额外reserve。
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
    writeback_record_t prior_writeback;
    bit [ADDR_WIDTH-1:0] expected_q0;
    int source_record;

    // 存在reserve时按正在申请的地址定位来源；没有reserve时使用尾push对应项。
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

    // 从已定位的原始事务还原查询对，并与本拍实际输入比较。
    source = seq.get_record(source_record);
    expected_q0 = '0;
    if (source_record > first_record) begin
        prior_writeback = seq.get_record(source_record - 1);
        expected_q0 = prior_writeback.addr;
    end
    if (sample.q0Addr !== expected_q0 || sample.q1Addr !== source.addr) begin
        `error($sformatf("%s queries expected=(0x%h,0x%h) actual=(0x%h,0x%h)",
            label, expected_q0, source.addr, sample.q0Addr, sample.q1Addr), "WBB_PIPELINE_QUERY")
    end
endfunction

// 检查第二批确实满槽等待：旧push继续发生，首个响应当拍不提前预留，下一拍恢复且再次产生重叠。
function void wbb_pipeline_test::check_stall_recovery(wbb_pipeline_sequence seq);
    activity_snapshot_t start_counts;
    activity_snapshot_t end_counts;

    start_counts = seq.starts[1];
    end_counts = seq.ends[1];
    check_count("pipeline push while reserve is blocked", end_counts.blocked_push_cycles - start_counts.blocked_push_cycles, 1, 1);
    check_count("pipeline blocked reserve cycles", end_counts.blocked_reserve_cycles - start_counts.blocked_reserve_cycles,
        wbb_pipeline_sequence::MIN_STALL_CYCLES, 1);
    check_count("pipeline full response still blocks reserve",
        end_counts.full_response_block_count - start_counts.full_response_block_count, 1, 1);
    check_count("pipeline reserve recovers on next edge",
        end_counts.full_response_recovery_count - start_counts.full_response_recovery_count, 1, 1);
    check_count("pipeline overlap after recovery", end_counts.resumed_overlap_count - start_counts.resumed_overlap_count, 1, 1);
    `info($sformatf("stage=1 blocked_push=%0d blocked_reserve=%0d full_response_block=%0d next_edge_recovery=%0d resumed_overlap=%0d",
        end_counts.blocked_push_cycles - start_counts.blocked_push_cycles,
        end_counts.blocked_reserve_cycles - start_counts.blocked_reserve_cycles,
        end_counts.full_response_block_count - start_counts.full_response_block_count,
        end_counts.full_response_recovery_count - start_counts.full_response_recovery_count,
        end_counts.resumed_overlap_count - start_counts.resumed_overlap_count), "WBB_PIPELINE_COVERAGE")
endfunction

// 两批之间已经没有待完成写回，空闲段内不应出现任何新的reserve、push、send或响应。
function void wbb_pipeline_test::check_idle_gap(wbb_pipeline_sequence seq, int index);
    activity_snapshot_t start_counts;
    activity_snapshot_t end_counts;

    start_counts = seq.idle_starts[index];
    end_counts = seq.idle_ends[index];
    check_count($sformatf("idle gap %0d reserve", index), end_counts.reserve_count - start_counts.reserve_count, 0);
    check_count($sformatf("idle gap %0d push", index), end_counts.push_count - start_counts.push_count, 0);
    check_count($sformatf("idle gap %0d send", index), end_counts.send_count - start_counts.send_count, 0);
    check_count($sformatf("idle gap %0d response", index), end_counts.response_count - start_counts.response_count, 0);
    check_count($sformatf("idle gap %0d sampled cycles", index), int'(end_counts.cycle - start_counts.cycle),
        wbb_pipeline_sequence::GAP_CYCLES, 1);
    `info($sformatf("idle_gap=%0d cycles=%0d reserve=0 push=0 send=0 response=0",
        index, end_counts.cycle - start_counts.cycle), "WBB_PIPELINE_COVERAGE")
endfunction
