// 所有功能case共用结果检查；只比较原始激励记录、公开IO及C++外部内存。
class mshr_scenario_test extends mshr_base_test;
    typedef mshr_expected_line line_queue_t[$];
    typedef mshr_scenario_sequence::replay_record_t replay_record_t;
    typedef replay_record_t replay_queue_t[$];

    `uvm_component_utils(mshr_scenario_test)

    function new(string name = "mshr_scenario_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern task run_scenario(mshr_scenario_sequence seq);
    extern function void check_data(mshr_scenario_sequence seq);
    extern function void check_fill_data(mshr_scenario_sequence seq);
    extern function void check_replay_data(mshr_scenario_sequence seq);
    extern function void check_memory_unchanged(mshr_scenario_sequence seq);
    extern function void check_coverage(mshr_scenario_sequence seq);
endclass

function void mshr_scenario_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.timeout_cycles = 2000000;
endfunction

// 启动激励、等待真实排空，再核对完整计数、原始数据及本case必须发生的场景。
task mshr_scenario_test::run_scenario(mshr_scenario_sequence seq);
    require_active_agent();
    seq.start(env.agent.sequencer);
    wait_for_drain();
    check_counts(seq.expected_alloc, seq.expected_merge, seq.replays.size());
    check_count("completed rounds", seq.completed_rounds, seq.required_rounds);
    check_data(seq);
    check_coverage(seq);
    `info($sformatf("rounds=%0d alloc=%0d merge=%0d replay=%0d fills_checked=%0d replay_values_checked=%0d",
        seq.completed_rounds, seq.expected_alloc, seq.expected_merge, seq.replays.size(),
        env.scoreboard.fill_samples.size(), env.scoreboard.replay_samples.size()), "MSHR_SCENARIO_COVERAGE")
endtask

// 分开核对fill、replay及外部MEM；所有期望来自sequence保存的原始输入。
function void mshr_scenario_test::check_data(mshr_scenario_sequence seq);
    check_fill_data(seq);
    check_replay_data(seq);
    check_memory_unchanged(seq);
endfunction

// 按块地址的生命周期顺序核对整行、way和dirty，允许不同Entry乱序填充。
function void mshr_scenario_test::check_fill_data(mshr_scenario_sequence seq);
    line_queue_t expected[bit [ADDR_WIDTH-1:0]];
    bit [ADDR_WIDTH-1:0] address;
    mshr_expected_line line;
    mshr_sample sample;

    foreach (seq.lines[index]) begin
        line = seq.lines[index];
        expected[line.addr].push_back(line);
    end
    foreach (env.scoreboard.fill_samples[index]) begin
        sample = env.scoreboard.fill_samples[index];
        address = (ADDR_WIDTH'(sample.fill_tag) << (INDEX_WIDTH + $clog2(BLOCK_SIZE))) |
            (ADDR_WIDTH'(sample.fill_index) << $clog2(BLOCK_SIZE));
        if (!expected.exists(address) || expected[address].size() == 0) begin
            `error($sformatf("Unexpected fill addr=%h", address), "MSHR_ORIGINAL_FILL")
        end else begin
            line = expected[address].pop_front();
            if (sample.fill_line !== line.final_data || sample.fill_dirty !== line.dirty || sample.fill_way !== WAY_WIDTH'(line.way)) begin
                `error($sformatf("Fill addr=%h way=%0d/%0d dirty=%b/%b actual=%h expected=%h",
                    address, sample.fill_way, line.way, sample.fill_dirty, line.dirty,
                    sample.fill_line, line.final_data), "MSHR_ORIGINAL_FILL")
            end
        end
    end
    foreach (expected[addr]) begin
        check_count("unmatched fills", expected[addr].size(), 0);
    end
endfunction

// CPU ID各自按复用次序匹配；读值只包含该Slot之前的写，写Slot只核对类型和ID。
function void mshr_scenario_test::check_replay_data(mshr_scenario_sequence seq);
    replay_queue_t expected[int];
    replay_record_t replay;
    mshr_sample sample;
    int cpu_id;

    foreach (seq.replays[index]) begin
        expected[int'(seq.replays[index].id)].push_back(seq.replays[index]);
    end
    foreach (env.scoreboard.replay_samples[index]) begin
        sample = env.scoreboard.replay_samples[index];
        cpu_id = sample.replay_payload_id;
        if (!expected.exists(cpu_id) || expected[cpu_id].size() == 0) begin
            `error($sformatf("Unexpected replay id=%0d", cpu_id), "MSHR_ORIGINAL_REPLAY")
        end else begin
            replay = expected[cpu_id].pop_front();
            if (sample.replay_payload_isWrite !== replay.is_write ||
                (!replay.is_write && sample.replay_payload_rData !== replay.data)) begin
                `error($sformatf("Replay id=%0d write=%b/%b data=%h/%h", cpu_id,
                    sample.replay_payload_isWrite, replay.is_write, sample.replay_payload_rData,
                    replay.data), "MSHR_ORIGINAL_REPLAY")
            end
        end
    end
    foreach (expected[id]) begin
        check_count("unmatched replays", expected[id].size(), 0);
    end
endfunction

// 经原C++ SparseMemory回读外部MEM，确认MSHR的fill和合并写没有误写后端内存。
function void mshr_scenario_test::check_memory_unchanged(mshr_scenario_sequence seq);
    bit [LINE_WIDTH-1:0] initial_data[bit [ADDR_WIDTH-1:0]];
    bit [LINE_WIDTH-1:0] actual;

    foreach (seq.lines[index]) begin
        initial_data[seq.lines[index].addr] = seq.lines[index].initial_data;
    end
    foreach (initial_data[addr]) begin
        // read_line经mshr_mem_read_line DPI读取RefModel/MEM/SparseMemory.hpp。
        env.memory.read_line(addr, actual);
        if (actual !== initial_data[addr]) begin
            `error($sformatf("External memory changed at %h", addr), "MSHR_EXTERNAL_MEMORY")
        end
    end
endfunction

// 只按实际接口计数判断场景是否命中；缺失目标明确报错，不能仅凭sequence已执行就算覆盖。
function void mshr_scenario_test::check_coverage(mshr_scenario_sequence seq);
    int actual;
    int delays[4] = '{1, 2, 7, 32};

    foreach (seq.required_hits[name]) begin
        actual = env.activity.hits.exists(name) ? env.activity.hits[name] : 0;
        if (actual < seq.required_hits[name]) begin
            `error($sformatf("Scenario %s observed=%0d required>=%0d", name, actual,
                seq.required_hits[name]), "MSHR_SCENARIO_MISSING")
        end
        `info($sformatf("scenario=%s observed=%0d required=%0d", name, actual,
            seq.required_hits[name]), "MSHR_EVENT_COVERAGE")
    end
    if (seq.check_all_positions) begin
        foreach (env.activity.entry_slot_hits[entry, slot, write_kind, edge_word]) begin
            if (env.activity.entry_slot_hits[entry][slot][write_kind][edge_word] == 0) begin
                `error($sformatf("Entry=%0d Slot=%0d write=%0d last_word=%0d not exercised", entry, slot, write_kind, edge_word), "MSHR_POSITION_MISSING")
            end
        end
    end
    if (seq.check_patterns) begin
        foreach (seq.pattern_counts[pattern]) begin
            check_count($sformatf("data pattern %0d", pattern), seq.pattern_counts[pattern],
                pattern inside {6, 7} ? LINE_WIDTH : WORDS_PER_BLOCK);
        end
    end
    if (seq.check_latencies) begin
        foreach (delays[index]) begin
            actual = env.activity.latency_hits.exists(delays[index]) ? env.activity.latency_hits[delays[index]] : 0;
            check_count($sformatf("actual response latency %0d", delays[index]), actual, 1);
        end
    end
endfunction
