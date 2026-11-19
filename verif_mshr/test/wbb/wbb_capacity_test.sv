// 检查 WBB 的 N 个槽全部占用时，第 N+1 笔不能提前预留；收到响应释放槽后才能继续。
// sequence 生成和提交数据；test 配置较长的响应延迟，通过 monitor 记录场景并检查结果。
class wbb_capacity_test extends wbb_base_test;
    typedef wbb_capacity_sequence::writeback_record_t writeback_record_t;

    localparam int WRITEBACK_COUNT = wbb_capacity_sequence::WRITEBACK_COUNT;
    localparam int MIN_WAIT_CYCLES = 4;
    localparam int RESPONSE_DELAY_CYCLES = 4 * WBB_ENTRIES + 16;

    uvm_analysis_imp #(wbb_sample, wbb_capacity_test) monitor_export;
    protected wbb_capacity_sequence seq;
    protected bit observing = 0;
    protected int reserve_seen = 0;
    protected int send_seen = 0;
    protected int response_seen = 0;
    protected bit [WBB_ENTRIES-1:0] first_slots = '0;
    protected int last_free_accepts = 0;
    protected int full_push_cycles = 0;
    protected int blocked_cycles = 0;
    protected int all_sent_full_cycles = 0;
    protected int full_response_count = 0;
    protected int recovered_accepts = 0;
    protected bit check_recovery_next = 0;
    protected logic [BUS_ID_WIDTH-1:0] released_id;

    `uvm_component_utils(wbb_capacity_test)

    function new(string name = "wbb_capacity_test",
        uvm_component parent = null);
        super.new(name, parent);
        monitor_export = new("monitor_export", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern function void write(wbb_sample tr);
    extern function void check_full_capacity(wbb_sample tr);
    extern function void check_waiting_request(wbb_sample tr);
    extern function void check_release_recovery(wbb_sample tr);
    extern function void count_events(wbb_sample tr);
    extern function void check_completion();
    extern function void check_capacity_coverage();
    extern function void check_memory_data();

endclass

function void wbb_capacity_test::build_phase(uvm_phase phase);
    int minimum_timeout;

    super.build_phase(phase);
    // 允许先接收 N 笔发送，但延迟返回响应，让槽在发送后继续占用。
    // 当前串行 driver 约每3拍提交一笔，4*N+16拍的延迟留出填满和等待的时间。
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = RESPONSE_DELAY_CYCLES;
    if (cfg.reserve_timeout_cycles < RESPONSE_DELAY_CYCLES + 16) begin
        cfg.reserve_timeout_cycles = RESPONSE_DELAY_CYCLES + 16;
    end
    minimum_timeout = clk_cfg.initial_reset_cycles + 3 * RESPONSE_DELAY_CYCLES + 8 * WBB_ENTRIES + 50;
    if (cfg.timeout_cycles < minimum_timeout) begin
        cfg.timeout_cycles = minimum_timeout;
    end
endfunction

function void wbb_capacity_test::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.agent.monitor.monitor_port.connect(monitor_export);
endfunction

// 启动 N+1 笔写回，等待最后一笔的内存响应，再检查事件数量、满槽场景和所有数据。
// observing 只开启本 case 的统计；原有 C++ 模型、scoreboard 和 IO 断言一直正常工作。
task wbb_capacity_test::run_sequence();
    require_active_agent();
    seq = wbb_capacity_sequence::type_id::create("seq");
    `info($sformatf("entries=%0d writebacks=%0d mem_max_pending=%0d response_delay_cycles=%0d min_wait_cycles=%0d",
        WBB_ENTRIES, WRITEBACK_COUNT, cfg.mem_max_pending, cfg.mem_write_latency_cycles,
        MIN_WAIT_CYCLES), "WBB_CAPACITY_CONFIG")
    observing = 1;
    seq.start(env.agent.sequencer);
    wait_for_drain();
    observing = 0;
    check_completion();
    check_capacity_coverage();
    check_memory_data();
endtask

// 接收 monitor 的沿前采样：先检查本拍输出，再记录本拍 reserve/send/response。
// 这样首个响应发生的这一拍仍按“全部槽占用”检查，不会把刚释放的槽提前算成空槽。
function void wbb_capacity_test::write(wbb_sample tr);
    if (!observing || tr.rst_n !== 1'b1) begin
        return;
    end
    check_release_recovery(tr);
    check_full_capacity(tr);
    count_events(tr);
endfunction

// 前 N 笔已预留且尚无响应时，必须一直 full=1、reserveOk=0，包括最后一笔 push 的那拍。
// 记录满状态下的 push，以及全部 N 笔都已发送但仍未释放的拍数。
function void wbb_capacity_test::check_full_capacity(wbb_sample tr);
    if (reserve_seen != WBB_ENTRIES || response_seen != 0) begin
        return;
    end
    if (tr.full !== 1'b1 || tr.reserveOk !== 1'b0) begin
        `error("All slots must remain occupied until the first response handshake", "WBB_CAPACITY_FULL")
    end
    if (tr.full === 1'b1 && tr.reserveOk === 1'b0) begin
        if (tr.push_en === 1'b1) begin
            full_push_cycles++;
        end
        if (send_seen == WBB_ENTRIES) begin
            all_sent_full_cycles++;
        end
    end
    check_waiting_request(tr);
    if (tr.memWriteResp_valid === 1'b1 && tr.memWriteResp_ready === 1'b1) begin
        if (tr.reserve_en !== 1'b1 || tr.full !== 1'b1 || tr.reserveOk !== 1'b0) begin
            `error("First response must occur while the extra reservation is still blocked", "WBB_CAPACITY_RELEASE")
        end
        full_response_count++;
        released_id = tr.memWriteResp_payload_id;
        check_recovery_next = 1;
    end
endfunction

// 本 case 使用 driver 持续保持第 N+1 笔请求的方式，检查等待时地址不变、没有提前 push。
// 只在确实观察到 full=1、reserveOk=0 和这笔请求时计数，避免未出现满槽等待也判通过。
function void wbb_capacity_test::check_waiting_request(wbb_sample tr);
    writeback_record_t extra;

    if (tr.reserve_en !== 1'b1) begin
        return;
    end
    extra = seq.get_record(WBB_ENTRIES);
    if (tr.reserve_addr !== extra.addr || tr.push_en !== 1'b0) begin
        `error("Blocked reservation must retain its address and must not push", "WBB_CAPACITY_REQUEST")
    end
    if (tr.full === 1'b1 && tr.reserveOk === 1'b0 && tr.reserve_addr === extra.addr) begin
        blocked_cycles++;
    end
endfunction

// 满槽时首个响应已经在上一拍握手，本拍必须能接受一直等待的第 N+1 笔 reserve。
// 此时只有刚释放的一个空槽，所以返回槽号必须等于上一拍的响应 ID。
function void wbb_capacity_test::check_release_recovery(wbb_sample tr);
    writeback_record_t extra;

    if (!check_recovery_next) begin
        return;
    end
    extra = seq.get_record(WBB_ENTRIES);
    if (tr.full !== 1'b0 || tr.reserveOk !== 1'b1 || tr.reserve_en !== 1'b1 ||
        tr.reserve_addr !== extra.addr || BUS_ID_WIDTH'(tr.reserveSlot) !== released_id) begin
        `error("The extra reservation must use the released slot on the next edge", "WBB_CAPACITY_RECOVERY")
    end else begin
        recovered_accepts++;
    end
    check_recovery_next = 0;
endfunction

// 统计实际 reserve、send 和响应事件，并确认前 N 笔预留用了 N 个不同槽。
// 这里只记录本 case 的命中情况；槽的完整生命周期继续由已有 C++ 模型和 IO 断言检查。
function void wbb_capacity_test::count_events(wbb_sample tr);
    int slot;

    if (tr.reserve_en === 1'b1 && tr.reserveOk === 1'b1) begin
        if (reserve_seen < WBB_ENTRIES) begin
            slot = int'(tr.reserveSlot);
            if ($isunknown(tr.reserveSlot) || slot < 0 || slot >= WBB_ENTRIES) begin
                `fatal("Capacity test observed an invalid reserved slot", "WBB_CAPACITY_SLOT")
            end
            if (first_slots[slot]) begin
                `error("Initial fill reused a slot before all slots were allocated", "WBB_CAPACITY_SLOT")
            end
            first_slots[slot] = 1;
            if (reserve_seen == WBB_ENTRIES - 1 && response_seen == 0 && tr.full === 1'b0) begin
                last_free_accepts++;
            end
        end
        reserve_seen++;
    end
    if (tr.send_valid === 1'b1 && tr.send_ready === 1'b1) begin
        send_seen++;
    end
    if (tr.memWriteResp_valid === 1'b1 && tr.memWriteResp_ready === 1'b1) begin
        response_seen++;
    end
endfunction

// 检查完整写回数量必须等于 N+1；不能用“请求与响应都少了一笔但数量相等”作为通过依据。
function void wbb_capacity_test::check_completion();
    check_count("capacity generated records", seq.get_record_count(), WRITEBACK_COUNT);
    check_writeback_counts(WRITEBACK_COUNT);
    check_count("capacity observed reserve", reserve_seen, WRITEBACK_COUNT);
    check_count("capacity observed send", send_seen, WRITEBACK_COUNT);
    check_count("capacity observed response", response_seen, WRITEBACK_COUNT);
endfunction

// 本 case 指定满槽、等待和释放恢复各需要出现多少次，再调用 base 的通用计数检查。
// 最后一个参数为1表示“至少”；这些容量要求只适用于本 case，不强加给其他 test。
function void wbb_capacity_test::check_capacity_coverage();
    check_count("capacity initial unique slots", $countones(first_slots), WBB_ENTRIES);
    check_count("capacity last free slot accepted", last_free_accepts, 1);
    check_count("capacity push while full", full_push_cycles, 1, 1);
    check_count("capacity blocked cycles", blocked_cycles, MIN_WAIT_CYCLES, 1);
    check_count("capacity all sent but still full", all_sent_full_cycles, MIN_WAIT_CYCLES, 1);
    check_count("capacity first full response", full_response_count, 1);
    check_count("capacity next-edge recovery", recovered_accepts, 1);
    check_count("capacity unchecked recovery", int'(check_recovery_next), 0);
    check_count("capacity scoreboard full cycles", env.scoreboard.full_cycles, 1, 1);
    `info($sformatf("slots=%b last_free=%0d full_push=%0d blocked_cycles=%0d all_sent_full_cycles=%0d full_response=%0d recovered=%0d",
        first_slots, last_free_accepts, full_push_cycles, blocked_cycles, all_sent_full_cycles,
        full_response_count, recovered_accepts), "WBB_CAPACITY_COVERAGE")
endfunction

// 全部响应完成后，逐地址比较 sequence 生成的数据与实际内存保存的数据，检查旧事务未被新事务覆盖。
function void wbb_capacity_test::check_memory_data();
    writeback_record_t record;

    for (int index = 0; index < seq.get_record_count(); index++) begin
        record = seq.get_record(index);
        // base test 的 check_memory_line() 统一经 DPI 回读 C++ 稀疏内存并比较整行数据。
        void'(check_memory_line(record.addr, record.line_data, $sformatf("capacity writeback %0d", index)));
    end
endfunction
