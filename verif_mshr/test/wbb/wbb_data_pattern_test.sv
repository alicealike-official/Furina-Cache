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
    extern function void check_preload();
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

    require_active_agent();

    preload_seq = wbb_data_pattern_sequence::type_id::create("preload_seq");
    preload_seq.preload_only = 1;
    preload_seq.start(env.agent.sequencer);
    wait_for_drain();
    check_preload();

    seq = wbb_data_pattern_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    wait_for_drain();
    check_count("generated patterns", seq.get_record_count(), EXPECTED_PATTERNS);
    check_writeback_counts(EXPECTED_WRITEBACKS);
    check_pattern_data();
    check_pattern_counts();
endtask

// 检查后续要写全0的地址，此时确实已经存入全1。
// 稀疏内存对从未写过的地址也返回0；先写全1，可以避免“根本没写入全0”却检查通过。
function void wbb_data_pattern_test::check_preload();
    // 继承自 wbb_base_test 的检查方法经 DPI 读取 C++ 稀疏内存；准备写入失败时立即 fatal。
    void'(check_memory_line(ADDR_WIDTH'(BLOCK_SIZE), '1, "zero-pattern preload", 1));
endfunction

// 逐笔取出 sequence 原先准备发送的地址和整行数据，再读取该地址的内存内容进行比较。
// 只有整行数据完全相同，才把对应数据模式的“已检查笔数”加1；不相同就报错。
function void wbb_data_pattern_test::check_pattern_data();
    pattern_record_t record;

    for (int index = 0; index < seq.get_record_count(); index++) begin
        record = seq.get_record(index);
        // base test 统一执行 C++ 稀疏内存回读和比较，子类只记录通过了哪一种数据模式。
        if (check_memory_line(record.addr, record.line_data, $sformatf("pattern %s", record.kind.name()))) begin
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
        check_count($sformatf("pattern %s", kind.name()), checked_patterns[pattern_index], expected_count);
        `info($sformatf("Pattern %s checked=%0d expected=%0d",
            kind.name(), checked_patterns[pattern_index], expected_count), "WBB_PATTERN_COVERAGE")
    end
endfunction
