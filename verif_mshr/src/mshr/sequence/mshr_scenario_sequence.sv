// 每条预置行的原始数据与最终写合成期望；这是case输入记录，不是第二个MSHR行为模型。
class mshr_expected_line extends uvm_object;
    bit [ADDR_WIDTH-1:0] addr;
    bit [LINE_WIDTH-1:0] initial_data;
    bit [LINE_WIDTH-1:0] final_data;
    bit dirty;
    int way;
    int entry = -1;
    int slot_count;
    `uvm_object_utils(mshr_expected_line)

    function new(string name = "mshr_expected_line");
        super.new(name);
    endfunction
endclass

// 公共场景工具只驱动接口及外部MEM，数据期望来自原始激励；DUT逐拍预测继续使用原C++模型。
class mshr_scenario_sequence extends mshr_base_sequence;
    typedef struct packed {
        bit [CPU_ID_WIDTH-1:0] id;
        bit is_write;
        bit [DATA_WIDTH-1:0] data;
    } replay_record_t;
    protected mshr_config cfg;
    protected mshr_activity_monitor obs;
    // C++ SparseMemory的SV封装，write_line经mshr_mem_write_line DPI预置内存。
    protected mshr_memory_store memory;
    mshr_expected_line lines[$];
    replay_record_t replays[$];
    int required_hits[string];
    int expected_alloc;
    int expected_merge;
    int completed_rounds;
    int required_rounds = 1;
    int next_cpu_id = 0;
    int pattern_counts[9];
    bit check_all_positions = 0;
    bit check_latencies = 0;
    bit check_patterns = 0;

    `uvm_object_utils(mshr_scenario_sequence)

    function new(string name = "mshr_scenario_sequence");
        super.new(name);
    endfunction

    extern virtual task pre_body();
    extern function bit [ADDR_WIDTH-1:0] block_address(int block_index);
    extern function bit [LINE_WIDTH-1:0] make_data(int pattern, int position);
    extern function mshr_expected_line prepare_line(int block_index, int way, int pattern = 8, int position = 0);
    extern task request_slot(mshr_expected_line line, bit is_write, int word_index, bit [DATA_WIDTH-1:0] data);
    extern function int choose_cpu_id();
    extern task query_line(mshr_expected_line first_line, mshr_expected_line second_line);
    extern task query_matrix(mshr_expected_line first_line, mshr_expected_line second_line);
    extern task release_all();
    extern task respond_entry(int entry);
    extern task prepare_group(int count, int slot_count, ref mshr_expected_line group[$],
        input int base_block = 0, input bit same_set = 0, input bit all_write = 0);
    extern task finish_round();
endclass

task mshr_scenario_sequence::pre_body();
    mshr_sequencer sequencer;

    super.pre_body();
    // 【防御性检查】场景需要环境传来的配置、IO观察器及外部MEM封装。
    if (!$cast(sequencer, get_sequencer()) || sequencer.observations == null || sequencer.memory == null) begin
        `fatal("Scenario requires MSHR sequencer observations and memory", "MSHR_SEQUENCE_CONFIG")
    end
    cfg = sequencer.cfg;
    obs = sequencer.observations;
    memory = sequencer.memory;
endtask

// 用块编号产生非零tag的对齐地址；字段推导只依赖公开参数。
function bit [ADDR_WIDTH-1:0] mshr_scenario_sequence::block_address(int block_index);
    return ADDR_WIDTH'((block_index + NUM_SETS) * BLOCK_SIZE);
endfunction

// 准备九类整行数据：0、1、交替位、逐字、逐字节、单1、单0及随机位。
function bit [LINE_WIDTH-1:0] mshr_scenario_sequence::make_data(int pattern, int position);
    bit [LINE_WIDTH-1:0] data;

    case (pattern)
        0: data = '0;
        1: data = '1;
        2, 3: for (int bit_index = 0; bit_index < LINE_WIDTH; bit_index++) data[bit_index] = bit'((bit_index + pattern) % 2);
        4: for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++)
            data[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('h10000000 + position * 256 + word_index);
        5: for (int byte_index = 0; byte_index < BLOCK_SIZE; byte_index++) data[byte_index * 8 +: 8] = 8'(byte_index + position);
        6: begin
            data = '0;
            data[position % LINE_WIDTH] = 1;
        end
        7: begin
            data = '1;
            data[position % LINE_WIDTH] = 0;
        end
        default: begin
            // 【防御性检查】随机数据生成失败时不能提交未准备的数据。
            if (!std::randomize(data)) `fatal("Line randomization failed", "MSHR_RANDOMIZE")
        end
    endcase
    return data;
endfunction

// 创建不可混淆的生命周期记录并预置外部C++ MEM；同址再次使用前由场景保证旧Entry排空。
function mshr_expected_line mshr_scenario_sequence::prepare_line(int block_index, int way, int pattern, int position);
    mshr_expected_line line;

    line = mshr_expected_line::type_id::create($sformatf("line_%0d", lines.size()));
    line.addr = block_address(block_index);
    line.way = way;
    line.initial_data = make_data(pattern, position);
    line.final_data = line.initial_data;
    // write_line在model/mshr_memory_store.sv中，经DPI调用原C++ SparseMemory，不访问DUT。
    memory.write_line(line.addr, line.initial_data);
    lines.push_back(line);
    return line;
endfunction

// 从实际已完成replay的CPU ID中选择空闲ID，轮换起点以遍历全部ID位型。
function int mshr_scenario_sequence::choose_cpu_id();
    int candidate;

    for (int offset = 0; offset < (1 << CPU_ID_WIDTH); offset++) begin
        candidate = (next_cpu_id + offset) % (1 << CPU_ID_WIDTH);
        if (!obs.cpu_pending[candidate]) begin
            next_cpu_id = (candidate + 1) % (1 << CPU_ID_WIDTH);
            return candidate;
        end
    end
    `fatal("No free CPU ID for planned stimulus", "MSHR_SEQUENCE_ID")
    return 0;
endfunction

// 提交首Slot或追加Slot，保存原始顺序；读期望只应用此前同字写，最终fill包含所有写。
task mshr_scenario_sequence::request_slot(mshr_expected_line line, bit is_write,
    int word_index, bit [DATA_WIDTH-1:0] data);
    mshr_transaction item;
    replay_record_t expected;

    item = mshr_transaction::type_id::create("slot_request");
    item.operation = line.slot_count == 0 ? MSHR_ALLOC : MSHR_MERGE;
    item.tag = TAG_WIDTH'(line.addr >> ($clog2(BLOCK_SIZE) + INDEX_WIDTH));
    item.index = INDEX_WIDTH'(line.addr >> $clog2(BLOCK_SIZE));
    item.way = WAY_WIDTH'(line.way);
    item.wordOff = WORD_OFF_WIDTH'(word_index);
    item.isWrite = is_write;
    item.wData = data;
    item.respId = CPU_ID_WIDTH'(choose_cpu_id());
    item.hasWb = bit'(lines.size() % 2);
    item.wbSlot = WBB_SLOT_WIDTH'(lines.size() % WBB_ENTRIES);
    item.q0Tag = item.tag;
    item.q0Index = item.index;
    item.q1Tag = item.tag;
    item.q1Index = item.index;

    expected.id = item.respId;
    expected.is_write = is_write;
    expected.data = line.final_data[word_index * DATA_WIDTH +: DATA_WIDTH];
    if (is_write) begin
        line.final_data[word_index * DATA_WIDTH +: DATA_WIDTH] = data;
        line.dirty = 1;
    end
    replays.push_back(expected);
    step(item);
    if (line.slot_count == 0) begin
        line.entry = item.selected_entry;
        expected_alloc++;
    end else begin
        expected_merge++;
    end
    line.slot_count++;
endtask

// 查询两条记录对应的块；null表示明确未分配的tag0块。
task mshr_scenario_sequence::query_line(mshr_expected_line first_line, mshr_expected_line second_line);
    bit [ADDR_WIDTH-1:0] first_addr;
    bit [ADDR_WIDTH-1:0] second_addr;

    first_addr = first_line == null ? '0 : first_line.addr;
    second_addr = second_line == null ? '0 : second_line.addr;
    query(TAG_WIDTH'(first_addr >> ($clog2(BLOCK_SIZE) + INDEX_WIDTH)), INDEX_WIDTH'(first_addr >> $clog2(BLOCK_SIZE)),
        TAG_WIDTH'(second_addr >> ($clog2(BLOCK_SIZE) + INDEX_WIDTH)), INDEX_WIDTH'(second_addr >> $clog2(BLOCK_SIZE)));
endtask

// 覆盖同址、异址、单口命中和双不命中；正确性由原模型及IO检查链判断。
task mshr_scenario_sequence::query_matrix(mshr_expected_line first_line, mshr_expected_line second_line);
    query_line(first_line, first_line);
    query_line(first_line, second_line);
    query_line(second_line, first_line);
    query_line(first_line, null);
    query_line(null, second_line);
    query_line(null, null);
endtask

// 放行全部通道并等待真实Entry释放，配置变更在完成采样后进行。
task mshr_scenario_sequence::release_all();
    obs.wait_cycles(1);
    cfg.mem_request_enable = 1;
    cfg.mem_response_enable = 1;
    cfg.mem_order = MSHR_MEM_FIFO;
    cfg.fill_enable = 1;
    cfg.replay_enable = 1;
    obs.wait_empty();
endtask

// 只返回指定已发送Entry的响应，握手后关闭新响应；既有呈现响应保持到接受。
task mshr_scenario_sequence::respond_entry(int entry);
    int target;

    obs.wait_cycles(1);
    target = obs.hits.exists("response") ? obs.hits["response"] + 1 : 1;
    cfg.selected_response_id = entry;
    cfg.mem_order = MSHR_MEM_SELECTED;
    cfg.mem_response_enable = 1;
    obs.wait_count("response", target);
    cfg.mem_response_enable = 0;
endtask

// 填充一组不同块；调用者暂停响应后，可安全地追加指定Slot数。
task mshr_scenario_sequence::prepare_group(int count, int slot_count, ref mshr_expected_line group[$],
    input int base_block, input bit same_set, input bit all_write);
    mshr_expected_line line;

    group.delete();
    for (int entry_index = 0; entry_index < count; entry_index++) begin
        line = prepare_line(base_block + (same_set ? entry_index * NUM_SETS : entry_index), entry_index % NUM_WAYS);
        group.push_back(line);
        for (int slot_index = 0; slot_index < slot_count; slot_index++) begin
            request_slot(line, all_write || bit'(slot_index % 2), slot_index % WORDS_PER_BLOCK,
                DATA_WIDTH'('h12340000 + completed_rounds * 256 + entry_index * 16 + slot_index));
        end
    end
endtask

// 结束一轮并记录完成数量；保持两个空态采样拍以检查伪发送、残留查询及锁。
task mshr_scenario_sequence::finish_round();
    release_all();
    query_line(null, null);
    obs.wait_cycles(2);
    completed_rounds++;
endtask
