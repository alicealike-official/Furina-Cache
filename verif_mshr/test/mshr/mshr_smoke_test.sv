class mshr_smoke_test extends mshr_base_test;
    `uvm_component_utils(mshr_smoke_test)

    function new(string name = "mshr_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual task run_sequence();
    extern function void check_smoke_data(mshr_smoke_sequence seq);
endclass

// 用基础读写验证框架连通性；预置数据和所有请求字段均来自sequence。
task mshr_smoke_test::run_sequence();
    mshr_smoke_sequence seq;
    require_active_agent();
    seq = mshr_smoke_sequence::type_id::create("seq");
    seq.prepare();
    for (int line_index = 0; line_index < 2; line_index++) begin
        // write_line是SV封装，内部用mshr_mem_write_line DPI预置C++ SparseMemory，不修改DUT。
        env.memory.write_line(seq.block_address(line_index), seq.initial_line(line_index));
    end
    seq.start(env.agent.sequencer);
    wait_for_drain();
    check_counts(2, 0, 2);
    check_count("read replay", env.scoreboard.read_replay_count, 1);
    check_count("write replay", env.scoreboard.write_replay_count, 1);
    check_smoke_data(seq);
endtask

// 将真实fill与原始激励期望逐行比较，同时确认写未命中没有直接改写外部MEM。
function void mshr_smoke_test::check_smoke_data(mshr_smoke_sequence seq);
    bit [LINE_WIDTH-1:0] memory_data;
    bit [LINE_WIDTH-1:0] expected_data;
    bit [ADDR_WIDTH-1:0] addr;
    int matching_fills;

    // 逐行定位实际fill，核对原始激励期望及目标way/dirty。
    for (int line_index = 0; line_index < 2; line_index++) begin
        addr = seq.block_address(line_index);
        expected_data = seq.expected_fill(line_index);
        matching_fills = 0;
        foreach (env.scoreboard.fill_samples[sample_index]) begin
            mshr_sample sample;
            sample = env.scoreboard.fill_samples[sample_index];
            if (sample.fill_index == INDEX_WIDTH'(addr >> $clog2(BLOCK_SIZE)) &&
                sample.fill_tag == TAG_WIDTH'(addr >> ($clog2(BLOCK_SIZE) + INDEX_WIDTH))) begin
                matching_fills++;
                if (sample.fill_line !== expected_data || sample.fill_dirty !== (line_index == 1) ||
                    sample.fill_way !== WAY_WIDTH'(line_index)) begin
                    `error("Actual fill differs from original stimulus", "MSHR_SMOKE_DATA")
                end
            end
        end

        // 确认每个目标只填充一次，再回读外部MEM，检查fill没有错误地写回后端。
        check_count($sformatf("fill line %0d", line_index), matching_fills, 1);
        // read_line通过mshr_mem_read_line DPI读取C++后端MEM，验证fill没有错误写回它。
        env.memory.read_line(addr, memory_data);
        if (memory_data !== seq.initial_line(line_index)) begin
            `error("Fill must not update external memory", "MSHR_SMOKE_MEMORY")
        end
    end

    // 独立核对读replay的数据和ID，以及写replay的CPU ID。
    expected_data = seq.initial_line(0);
    foreach (env.scoreboard.replay_samples[sample_index]) begin
        mshr_sample sample;
        sample = env.scoreboard.replay_samples[sample_index];
        if (!sample.replay_payload_isWrite &&
            (sample.replay_payload_id !== CPU_ID_WIDTH'(0) ||
            sample.replay_payload_rData !== expected_data[0 +: DATA_WIDTH])) begin
            `error("Read replay differs from original stimulus", "MSHR_SMOKE_DATA")
        end
        if (sample.replay_payload_isWrite && sample.replay_payload_id !== {CPU_ID_WIDTH{1'b1}}) begin
            `error("Write replay CPU ID differs from original stimulus", "MSHR_SMOKE_DATA")
        end
    end

    // 数据和事件检查结束后记录基础场景命中。
    `info("read=1 write=1 fills_checked=2 external_memory_unchanged=2", "MSHR_SMOKE_COVERAGE")
endfunction
