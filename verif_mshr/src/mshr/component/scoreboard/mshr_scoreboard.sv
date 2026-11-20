class mshr_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(mshr_compare_item, mshr_scoreboard) compare_export;
    int checked_cycles;
    int alloc_count;
    int merge_count;
    int send_count;
    int response_count;
    int fill_count;
    int replay_count;
    int release_count;
    int read_replay_count;
    int write_replay_count;
    mshr_sample fill_samples[$];
    mshr_sample replay_samples[$];
    // 这里只记录实际IO事件及归属，用于守恒/锁检查；行为预测来自C++ MSHR。
    protected bit occupied[MSHR_ENTRIES];
    protected bit sent[MSHR_ENTRIES];
    protected bit returned[MSHR_ENTRIES];
    protected bit filled[MSHR_ENTRIES];
    protected logic [TAG_WIDTH-1:0] tags[MSHR_ENTRIES];
    protected logic [INDEX_WIDTH-1:0] indices[MSHR_ENTRIES];
    protected logic [WAY_WIDTH-1:0] ways[MSHR_ENTRIES];
    protected int slot_count[MSHR_ENTRIES];
    protected int completed[MSHR_ENTRIES];
    protected bit cpu_pending[1 << CPU_ID_WIDTH];
    protected bit cpu_write[1 << CPU_ID_WIDTH];
    protected int cpu_entry[1 << CPU_ID_WIDTH];
    protected int cpu_slot[1 << CPU_ID_WIDTH];

    `uvm_component_utils(mshr_scoreboard)

    function new(string name = "mshr_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent cannot be null")
        end
        compare_export = new("compare_export", this);
    endfunction

    extern function void write(mshr_compare_item item);
    extern function void compare_queries(mshr_compare_item item);
    extern function void compare_outputs(mshr_compare_item item);
    extern function void check_history(mshr_sample sample);
    extern function void record_events(mshr_sample sample);
    extern function void register_slot(int entry, bit is_write, int cpu_id);
    extern function int find_fill_entry(mshr_sample sample);
    extern function bit is_idle();
    extern virtual function void check_phase(uvm_phase phase);
    extern virtual function void report_phase(uvm_phase phase);
endclass

// 接收C++预测与同一拍的实际快照，先检查沿前状态，再登记本沿接受的事件。
function void mshr_scoreboard::write(mshr_compare_item item);
    if (item == null || item.actual_sample == null) begin
        `fatal("Null MSHR comparison item", "MSHR_COMPARE")
    end
    checked_cycles++;
    compare_queries(item);
    compare_outputs(item);
    check_history(item.actual_sample);
    record_events(item.actual_sample);
endfunction

// 只在查询命中、存在空Slot/Entry时比较有效索引，避免与C++的-1哨兵硬比较。
function void mshr_scoreboard::compare_queries(mshr_compare_item item);
    mshr_sample sample;
    sample = item.actual_sample;

    // 检查空Entry反馈；只有hasFree有效时才比较返回的索引。
    if (sample.hasFree !== (item.expected_hasFree != 0) ||
        (item.expected_hasFree && sample.freeEntry !== ENTRY_WIDTH'(item.expected_freeEntry))) begin
        `error("Free entry differs from C++ MSHR", "MSHR_CAPACITY")
    end

    // 先比较两路是否命中，再检查命中时才有意义的Entry和Slot字段。
    if (sample.m0_hit !== (item.expected_m0_hit != 0) ||
        sample.m1_hit !== (item.expected_m1_hit != 0)) begin
        `error("Query hit differs from C++ MSHR", "MSHR_QUERY")
    end
    if (item.expected_m0_hit &&
        (sample.m0_entry !== ENTRY_WIDTH'(item.expected_m0_entry) ||
        sample.m0_mergeable !== (item.expected_m0_mergeable != 0) ||
        sample.m0_slotFree !== (item.expected_m0_slotFree != 0) ||
        (item.expected_m0_slotFree && sample.m0_freeSlot !== SLOT_WIDTH'(item.expected_m0_freeSlot)))) begin
        `error("Query 0 fields differ from C++ MSHR", "MSHR_QUERY")
    end
    if (item.expected_m1_hit &&
        (sample.m1_entry !== ENTRY_WIDTH'(item.expected_m1_entry) ||
        sample.m1_mergeable !== (item.expected_m1_mergeable != 0) ||
        sample.m1_slotFree !== (item.expected_m1_slotFree != 0) ||
        (item.expected_m1_slotFree && sample.m1_freeSlot !== SLOT_WIDTH'(item.expected_m1_freeSlot)))) begin
        `error("Query 1 fields differ from C++ MSHR", "MSHR_QUERY")
    end
endfunction

// expected_*由mshr_predictor经mshr_ref_step DPI取得，模型在RefModel/Cache/MSHR.hpp。
// 写replay的数据无功能含义；其Stream保持另由IO断言检查。
function void mshr_scoreboard::compare_outputs(mshr_compare_item item);
    mshr_sample sample;
    sample = item.actual_sample;

    // 比较本拍呈现的读请求，包括背压时保持的地址和ID。
    if (sample.memReadReq_valid !== (item.expected_memReadReq_valid != 0) ||
        (item.expected_memReadReq_valid &&
        (sample.memReadReq_payload_addr !== item.expected_memReadReq_payload_addr ||
        sample.memReadReq_payload_id !== BUS_ID_WIDTH'(item.expected_memReadReq_payload_id)))) begin
        `error("Memory read request differs from C++ MSHR", "MSHR_SEND")
    end

    // 比较填充目标、整行数据和dirty，避免不同Entry之间串行。
    if (sample.fill_en !== (item.expected_fill_en != 0) ||
        (item.expected_fill_en &&
        (sample.fill_tag !== TAG_WIDTH'(item.expected_fill_tag) ||
        sample.fill_index !== INDEX_WIDTH'(item.expected_fill_index) ||
        sample.fill_way !== WAY_WIDTH'(item.expected_fill_way) ||
        sample.fill_dirty !== (item.expected_fill_dirty != 0) ||
        sample.fill_line !== item.expected_fill_line))) begin
        `error("Fill target/data/dirty differs from C++ MSHR", "MSHR_FILL")
    end

    // 比较重放类型和CPU ID；仅对读Slot比较返回数据。
    if (sample.replay_valid !== (item.expected_replay_valid != 0) ||
        (item.expected_replay_valid &&
        (sample.replay_payload_isWrite !== (item.expected_replay_payload_isWrite != 0) ||
        sample.replay_payload_id !== CPU_ID_WIDTH'(item.expected_replay_payload_id) ||
        (!item.expected_replay_payload_isWrite &&
        sample.replay_payload_rData !== item.expected_replay_payload_rData)))) begin
        `error("Replay type/ID/read data differs from C++ MSHR", "MSHR_REPLAY")
    end
endfunction

// 用接受历史找出fill所属Entry；fill接口没有Entry字段，因此按tag/index/way匹配。
function int mshr_scoreboard::find_fill_entry(mshr_sample sample);
    for (int entry = 0; entry < MSHR_ENTRIES; entry++) begin
        if (occupied[entry] && tags[entry] == sample.fill_tag && indices[entry] == sample.fill_index && ways[entry] == sample.fill_way) begin
            return entry;
        end
    end
    return -1;
endfunction

// 从IO接受历史检查全lockMask、发送/响应/填充归属和每个CPU ID的顺序。
// 所有判断都使用本沿之前的记录，不能因同拍fill/响应而允许提前replay。
function void mshr_scoreboard::check_history(mshr_sample sample);
    logic [LOCK_WIDTH-1:0] expected_locks;
    int entry;

    // 由沿前有效Entry重建整张锁矩阵，检查没有漏锁或残留锁。
    expected_locks = '0;
    for (int scan_entry = 0; scan_entry < MSHR_ENTRIES; scan_entry++) begin
        if (occupied[scan_entry]) begin
            expected_locks[int'(indices[scan_entry]) * NUM_WAYS + int'(ways[scan_entry])] = 1;
        end
    end
    if (sample.lockMask !== expected_locks) begin
        `error("lockMask differs from accepted allocation/replay history", "MSHR_LOCK")
    end

    // 检查新分配的CPU ID、空Entry、set/way以及块地址唯一性。
    if (sample.alloc_en) begin
        if (cpu_pending[sample.alloc_respId]) begin
            `fatal("Allocation reuses a CPU ID still pending before this edge", "MSHR_ENV_CPU_ID")
        end
        if ($isunknown({sample.alloc_index, sample.alloc_way}) || !sample.hasFree || int'(sample.alloc_index) >= NUM_SETS ||
            int'(sample.alloc_way) >= NUM_WAYS) begin
            `fatal("Allocation uses invalid resources", "MSHR_ENV_ALLOC")
        end
        if ($isunknown(sample.freeEntry) || int'(sample.freeEntry) >= MSHR_ENTRIES) begin
            `fatal("DUT selected an invalid freeEntry", "MSHR_DUT_ALLOC_OWNER")
        end
        if (occupied[sample.freeEntry]) begin
            `fatal("DUT selected an already occupied Entry", "MSHR_DUT_ALLOC_OWNER")
        end
        if (expected_locks[int'(sample.alloc_index) * NUM_WAYS + int'(sample.alloc_way)]) begin
            `fatal("Upstream allocated an already occupied set/way", "MSHR_ENV_ALLOC")
        end
        for (int scan_entry = 0; scan_entry < MSHR_ENTRIES; scan_entry++) begin
            if (occupied[scan_entry] && tags[scan_entry] == sample.alloc_tag && indices[scan_entry] == sample.alloc_index) begin
                `fatal("Allocation duplicates an occupied block", "MSHR_ENV_ALLOC")
            end
        end
    end

    // 检查合并目标仍在SEND/MISS_WAIT，并且有空Slot。
    if (sample.merge_en) begin
        if (cpu_pending[sample.merge_respId]) begin
            `fatal("Merge reuses a CPU ID still pending before this edge", "MSHR_ENV_CPU_ID")
        end
        if ($isunknown(sample.merge_entry) || int'(sample.merge_entry) >= MSHR_ENTRIES) begin
            `fatal("Merge entry invalid", "MSHR_ENV_MERGE")
        end
        entry = sample.merge_entry;
        if (!occupied[entry] || returned[entry] || slot_count[entry] >= MSHR_MAX_PENDING) begin
            `fatal("Merge requires SEND/MISS_WAIT and a free slot", "MSHR_ENV_MERGE")
        end
    end

    // 检查读请求属于已分配但尚未发送的Entry。
    if (sample.memReadReq_valid) begin
        if ($isunknown(sample.memReadReq_payload_id) || int'(sample.memReadReq_payload_id) >= MSHR_ENTRIES) begin
            `fatal("Invalid full memory request ID", "MSHR_SEND_ID")
        end
        entry = sample.memReadReq_payload_id;
        if (!occupied[entry] || sent[entry]) begin
            `error("Memory request has no unsent allocated owner", "MSHR_SEND_OWNER")
        end
    end

    // 检查响应完整ID及归属，禁止未发先回和重复响应。
    if (sample.memReadResp_valid) begin
        if ($isunknown(sample.memReadResp_payload_id) || int'(sample.memReadResp_payload_id) >= MSHR_ENTRIES) begin
            `fatal("Invalid full memory response ID", "MSHR_ENV_RESPONSE")
        end
        entry = sample.memReadResp_payload_id;
        if (!occupied[entry] || !sent[entry] || returned[entry]) begin
            `fatal("Response requires an earlier request handshake", "MSHR_ENV_RESPONSE")
        end
    end

    // 按分配目标识别fill，确认已收到原始行且没有重复填充。
    if (sample.fill_en) begin
        entry = find_fill_entry(sample);
        if (entry < 0) begin
            `fatal("Fill has no allocated owner", "MSHR_FILL_OWNER")
        end
        if (!returned[entry] || filled[entry]) begin
            `fatal("Fill precedes response or duplicates completed fill", "MSHR_FILL_OWNER")
        end
    end

    // 按CPU ID回溯Slot，检查先填充、后按序重放。
    if (sample.replay_valid) begin
        if ($isunknown({sample.replay_payload_id, sample.replay_payload_isWrite})) begin
            `fatal("Unknown replay ID/type", "MSHR_REPLAY_OWNER")
        end
        if (!cpu_pending[sample.replay_payload_id]) begin
            `fatal("Replay has no accepted CPU request", "MSHR_REPLAY_OWNER")
        end
        entry = cpu_entry[sample.replay_payload_id];
        if (!filled[entry] || cpu_slot[sample.replay_payload_id] != completed[entry] ||
            sample.replay_payload_isWrite != cpu_write[sample.replay_payload_id]) begin
            `fatal("Replay precedes fill or violates slot order/type", "MSHR_REPLAY_OWNER")
        end
    end
endfunction

// 登记一笔已接受的Slot及CPU ID；这是输入/响应配对记录，不预测读数据。
function void mshr_scoreboard::register_slot(int entry, bit is_write, int cpu_id);
    if (cpu_pending[cpu_id]) begin
        `fatal("CPU ID reused before replay handshake", "MSHR_ENV_CPU_ID")
    end
    cpu_pending[cpu_id] = 1;
    cpu_write[cpu_id] = is_write;
    cpu_entry[cpu_id] = entry;
    cpu_slot[cpu_id] = slot_count[entry];
    slot_count[entry]++;
endfunction

// 检查沿前条件之后推进实际历史；先处理旧replay，再接受本沿的新alloc/merge。
function void mshr_scoreboard::record_events(mshr_sample sample);
    int entry;

    // 先记录旧Slot的重放；最后一笔才释放Entry及其历史占用。
    if (sample.replay_valid && sample.replay_ready) begin
        entry = cpu_entry[sample.replay_payload_id];
        cpu_pending[sample.replay_payload_id] = 0;
        completed[entry]++;
        replay_count++;
        if (sample.replay_payload_isWrite) begin
            write_replay_count++;
        end else begin
            read_replay_count++;
        end
        replay_samples.push_back(sample);
        if (completed[entry] == slot_count[entry]) begin
            occupied[entry] = 0;
            sent[entry] = 0;
            returned[entry] = 0;
            filled[entry] = 0;
            slot_count[entry] = 0;
            completed[entry] = 0;
            release_count++;
        end
    end

    // 登记实际接受的fill，保留原样采样供test检查整行数据。
    if (sample.fill_en && sample.fillReady) begin
        entry = find_fill_entry(sample);
        filled[entry] = 1;
        fill_count++;
        fill_samples.push_back(sample);
    end

    // 登记本拍内存响应，随后登记本拍新读请求，各自只计握手。
    if (sample.memReadResp_valid && sample.memReadResp_ready) begin
        returned[sample.memReadResp_payload_id] = 1;
        response_count++;
    end
    if (sample.memReadReq_valid && sample.memReadReq_ready) begin
        sent[sample.memReadReq_payload_id] = 1;
        send_count++;
    end

    // 最后登记新Entry和追加Slot；合法性已按沿前历史检查过。
    if (sample.alloc_en) begin
        entry = sample.freeEntry;
        occupied[entry] = 1;
        tags[entry] = sample.alloc_tag;
        indices[entry] = sample.alloc_index;
        ways[entry] = sample.alloc_way;
        register_slot(entry, sample.alloc_isWrite, sample.alloc_respId);
        alloc_count++;
    end
    if (sample.merge_en) begin
        register_slot(sample.merge_entry, sample.merge_isWrite, sample.merge_respId);
        merge_count++;
    end
endfunction

// 只检查实际IO记录是否排空；environment还会查询C++模型及内存代理。
function bit mshr_scoreboard::is_idle();
    foreach (occupied[entry]) begin
        if (occupied[entry]) begin
            return 0;
        end
    end
    foreach (cpu_pending[id]) begin
        if (cpu_pending[id]) begin
            return 0;
        end
    end
    return 1;
endfunction

function void mshr_scoreboard::check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!is_idle() || alloc_count != send_count || send_count != response_count ||
        response_count != fill_count || fill_count != release_count ||
        alloc_count + merge_count != replay_count) begin
        `error("Entry/Slot transactions did not drain consistently", "MSHR_DRAIN")
    end
    if (checked_cycles == 0) begin
        `error("No post-reset samples checked", "MSHR_EMPTY_TEST")
    end
endfunction

function void mshr_scoreboard::report_phase(uvm_phase phase);
    super.report_phase(phase);
    `info($sformatf("cycles=%0d alloc=%0d merge=%0d send=%0d response=%0d fill=%0d replay=%0d release=%0d",
        checked_cycles, alloc_count, merge_count, send_count, response_count, fill_count,
        replay_count, release_count), "MSHR_COUNTS")
endfunction
