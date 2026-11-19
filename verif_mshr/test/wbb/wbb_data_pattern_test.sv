// 检查写入 WBB 的整行数据，最终是否原样写到内存。
// pattern 在这里指“数据模式”，也就是整行中各个位、字节和字的取值，
// 例如每一位都是0、每一位都是1，或者各个字依次取1、2、3等不同值。
// sequence 负责生成和发送这些数据；test 负责启动 sequence、等待完成并检查结果。
class wbb_data_pattern_test extends wbb_base_test;
    typedef wbb_data_pattern_sequence::pattern_kind_t pattern_kind_t;
    typedef wbb_data_pattern_sequence::pattern_record_t pattern_record_t;

    localparam int RANDOM_LINE_COUNT = wbb_data_pattern_sequence::RANDOM_LINE_COUNT;
    localparam int PATTERN_KIND_COUNT = wbb_data_pattern_sequence::PATTERN_KIND_COUNT;
    localparam int EXPECTED_PATTERNS = wbb_data_pattern_sequence::EXPECTED_PATTERNS;
    localparam int EXPECTED_WRITEBACKS = wbb_data_pattern_sequence::EXPECTED_WRITEBACKS;

    protected wbb_data_pattern_sequence seq;
    // 分别记录九种数据模式中，有多少笔写回的数据已经比较正确。
    protected int unsigned checked_patterns[PATTERN_KIND_COUNT] = '{default: 0};

    `uvm_component_utils(wbb_data_pattern_test)

    function new(string name = "wbb_data_pattern_test",
        uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern task wait_for_drain();
    extern function void check_preload();
    extern function void check_writeback_counts();
    extern function void check_pattern_data();
    extern function void check_pattern_counts();

endclass

function void wbb_data_pattern_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 单个1和单个0都要依次出现在整行的每一位，会产生较多写回事务，因此增加总超时拍数。
    // 如果外部已设置更大的超时值，就保留它；cfg 是 test 和 env 共用的配置对象。
    if (cfg.timeout_cycles < EXPECTED_WRITEBACKS * 8 + 100) begin
        cfg.timeout_cycles = EXPECTED_WRITEBACKS * 8 + 100;
    end
endfunction

// 先启动一笔全1写回，等内存响应完成并确认写入正确，再启动九种数据模式的测试。
// 所有写回完成后，检查事务数量、内存中的数据，以及每种模式实际检查了多少笔。
// 本 task 只负责安排执行顺序，地址和数据由 sequence 生成。
task wbb_data_pattern_test::run_sequence();
    wbb_data_pattern_sequence preload_seq;

    if (env.agent.sequencer == null) begin
        `fatal("Data patterns require an active WBB agent", "WBB_NO_SEQUENCER")
    end

    preload_seq = wbb_data_pattern_sequence::type_id::create("preload_seq");
    preload_seq.preload_only = 1;
    preload_seq.start(env.agent.sequencer);
    wait_for_drain();
    check_preload();

    seq = wbb_data_pattern_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    wait_for_drain();
    check_writeback_counts();
    check_pattern_data();
    check_pattern_counts();
endtask

// sequence 返回时，driver 只保证 reserve 和 push 已完成，内存写请求和响应可能还没结束。
// 先等待4个时钟下降沿，再等到 WBB 参考模型没有占用槽、内存 driver 没有待完成的请求。
// env.is_idle() 通过 DPI 查询 C++ WBB 模型，并检查 SV 响应队列；run_phase 的总超时防止一直等待。
task wbb_data_pattern_test::wait_for_drain();
    repeat (4) @(negedge vif.clk);
    while (!env.is_idle()) begin
        @(negedge vif.clk);
    end
endtask

// 检查后续要写全0的地址，此时确实已经存入全1。
// 稀疏内存对从未写过的地址也返回0；先写全1，可以避免“根本没写入全0”却检查通过。
function void wbb_data_pattern_test::check_preload();
    bit [LINE_WIDTH-1:0] actual_data;

    // read_actual() 定义在 model/wbb_memory_store.sv，通过 DPI 读取 C++ SparseMemory。
    // TB 内存模型在 DUT 的 send 接口完成握手时写入数据；这里读取该模型保存的内容。
    env.memory.read_actual(BLOCK_SIZE, actual_data);
    if (actual_data !== {LINE_WIDTH{1'b1}}) begin
        `fatal("Failed to initialize the zero-pattern address with all ones", "WBB_PATTERN_PRELOAD")
    end
endfunction

// 检查 sequence 生成的数据笔数，以及 reserve 成功、push、send 握手、响应握手的次数。
// 默认512位行应生成1062笔测试数据，另加最开始的1笔全1写回，四项事务计数都应为1063。
// 这样即使某笔数据恰好是全0，也不能因为少发送了一笔事务而直接通过检查。
function void wbb_data_pattern_test::check_writeback_counts();
    if (seq.get_record_count() != EXPECTED_PATTERNS ||
        env.scoreboard.reserve_count !== EXPECTED_WRITEBACKS ||
        env.scoreboard.push_count !== EXPECTED_WRITEBACKS ||
        env.scoreboard.send_count !== EXPECTED_WRITEBACKS ||
        env.scoreboard.response_count !== EXPECTED_WRITEBACKS) begin
        `error($sformatf("Expected %0d patterns and %0d writebacks including preload; patterns=%0d reserve=%0d push=%0d send=%0d response=%0d",
            EXPECTED_PATTERNS, EXPECTED_WRITEBACKS, seq.get_record_count(), env.scoreboard.reserve_count,
            env.scoreboard.push_count, env.scoreboard.send_count, env.scoreboard.response_count),
            "WBB_PATTERN_COUNT")
    end
endfunction

// 逐笔取出 sequence 原先准备发送的地址和整行数据，再读取该地址的内存内容进行比较。
// 只有整行数据完全相同，才把对应数据模式的“已检查笔数”加1；不相同就报错。
function void wbb_data_pattern_test::check_pattern_data();
    bit [LINE_WIDTH-1:0] actual_data;
    pattern_record_t record;

    for (int index = 0; index < seq.get_record_count(); index++) begin
        record = seq.get_record(index);
        // read_actual() 是 model/wbb_memory_store.sv 中的 SV 方法，内部调用 sparse_mem_read_line DPI。
        // C++ 存储实现在 RefModel/MEM/SparseMemory.hpp；这里读取 DUT 经 send 握手写入 TB 内存的数据。
        env.memory.read_actual(record.addr, actual_data);
        if (actual_data !== record.line_data) begin
            `error($sformatf("Pattern %s mismatch at 0x%h: expected=%h actual=%h",
                record.kind.name(), record.addr, record.line_data, actual_data), "WBB_PATTERN_DATA")
        end else begin
            checked_patterns[int'(record.kind)]++;
        end
    end
endfunction

// 检查九种数据模式是否都完成了规定数量的数据比较，缺少任何一种都报错。
// 六种固定数据各1笔；单个1和单个0依次放到每一位，各 LINE_WIDTH 笔；随机数据32笔。
function void wbb_data_pattern_test::check_pattern_counts();
    pattern_kind_t kind;
    int expected_count;

    for (int pattern_index = 0; pattern_index < PATTERN_KIND_COUNT; pattern_index++) begin
        kind = pattern_kind_t'(pattern_index);
        case (kind)
            wbb_data_pattern_sequence::WALKING_ONE,
            wbb_data_pattern_sequence::WALKING_ZERO: expected_count = LINE_WIDTH;
            wbb_data_pattern_sequence::RANDOM_LINE: expected_count = RANDOM_LINE_COUNT;
            default: expected_count = 1;
        endcase
        if (checked_patterns[pattern_index] !== expected_count) begin
            `error($sformatf("Pattern %s checked=%0d expected=%0d",
                kind.name(), checked_patterns[pattern_index], expected_count), "WBB_PATTERN_COVERAGE")
        end
        `info($sformatf("Pattern %s checked=%0d expected=%0d",
            kind.name(), checked_patterns[pattern_index], expected_count), "WBB_PATTERN_COVERAGE")
    end
endfunction
