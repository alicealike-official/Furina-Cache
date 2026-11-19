// 供多阶段场景复用的激励工具，只使用sequencer传来的配置和IO事件，不访问DUT内部或C++模型。
class wbb_scenario_sequence extends wbb_base_sequence;
    typedef struct packed {
        bit [ADDR_WIDTH-1:0] addr;
        bit [LINE_WIDTH-1:0] line_data;
    } writeback_record_t;
    protected wbb_config cfg;
    protected wbb_activity_monitor obs;
    protected writeback_record_t records[$];
    `uvm_object_utils(wbb_scenario_sequence)

    function new(string name = "wbb_scenario_sequence");
        super.new(name);
    endfunction

    extern virtual task pre_body();
    extern function bit [ADDR_WIDTH-1:0] block_addr(int index);
    extern function bit [LINE_WIDTH-1:0] make_line(int index);
    extern task send_line(int index, bit [ADDR_WIDTH-1:0] q0 = '0,
        bit [ADDR_WIDTH-1:0] q1 = '0, int push_delay_cycles = 1);
    extern task send_data(bit [ADDR_WIDTH-1:0] addr, bit [LINE_WIDTH-1:0] line_data,
        bit [ADDR_WIDTH-1:0] q0 = '0, bit [ADDR_WIDTH-1:0] q1 = '0, int push_delay_cycles = 1);
    extern task send_batch(int first_index, int hold_cycles,
        bit [ADDR_WIDTH-1:0] q0 = '0, bit [ADDR_WIDTH-1:0] q1 = '0);
    extern task release_response(int id);
    extern task query_pairs(bit [ADDR_WIDTH-1:0] a, bit [ADDR_WIDTH-1:0] b, bit [ADDR_WIDTH-1:0] miss);
    extern function int get_record_count();
    extern function writeback_record_t get_record(int index);
endclass

task wbb_scenario_sequence::pre_body();
    wbb_sequencer sqr;

    super.pre_body();
    if (!$cast(sqr, get_sequencer())) begin
        `fatal("Scenario sequence requires wbb_sequencer", "WBB_SEQUENCE_CONFIG")
    end
    cfg = sqr.cfg;
    obs = sqr.observations;
    records.delete();
endtask

// 按编号生成非零块地址，遇到负编号或地址溢出时明确报错。
function bit [ADDR_WIDTH-1:0] wbb_scenario_sequence::block_addr(int index);
    longint unsigned value;

    value = (64'(index) + 1) * BLOCK_SIZE;
    if (index < 0 || value == 0 || 64'(ADDR_WIDTH'(value)) != value) begin
        `fatal("Scenario block address is out of range", "WBB_SEQUENCE_ADDRESS")
    end
    return ADDR_WIDTH'(value);
endfunction

// 生成每个字都可区分的数据；不同编号使用不同的整行内容。
function bit [LINE_WIDTH-1:0] wbb_scenario_sequence::make_line(int index);
    bit [LINE_WIDTH-1:0] data;

    for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
        data[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'((index + 1) * 'h10000 + word_index);
    end
    return data;
endfunction

// 用编号生成地址和数据，再提交完整写回；查询地址和push延迟由具体场景指定。
task wbb_scenario_sequence::send_line(int index, bit [ADDR_WIDTH-1:0] q0,
    bit [ADDR_WIDTH-1:0] q1, int push_delay_cycles);
    send_data(block_addr(index), make_line(index), q0, q1, push_delay_cycles);
endtask

// 先保存原始数据，再交给已有完整事务接口；不自行驱动reserve/push信号。
task wbb_scenario_sequence::send_data(bit [ADDR_WIDTH-1:0] addr, bit [LINE_WIDTH-1:0] line_data,
    bit [ADDR_WIDTH-1:0] q0, bit [ADDR_WIDTH-1:0] q1, int push_delay_cycles);
    writeback_record_t record;

    record.addr = addr;
    record.line_data = line_data;
    records.push_back(record);
    writeback_line(addr, line_data, q0, q1, push_delay_cycles);
endtask

// 提交包含N笔完整写回的批次，先全部预留，再等待指定拍数，最后逐笔push。
// 该操作仅用于显式延迟模式；它不产生reserve和push同拍。
task wbb_scenario_sequence::send_batch(int first_index, int hold_cycles,
    bit [ADDR_WIDTH-1:0] q0, bit [ADDR_WIDTH-1:0] q1);
    wbb_batch_transaction batch;
    writeback_record_t record;

    batch = wbb_batch_transaction::type_id::create("batch");
    batch.hold_cycles = hold_cycles;
    batch.q0Addr = q0;
    batch.q1Addr = q1;
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        wbb_transaction tr;
        tr = wbb_transaction::type_id::create($sformatf("entry_%0d", index));
        tr.addr = block_addr(first_index + index);
        tr.line_data = make_line(first_index + index);
        tr.q0Addr = tr.addr;
        tr.q1Addr = q1;
        batch.entries.push_back(tr);
        record.addr = tr.addr;
        record.line_data = tr.line_data;
        records.push_back(record);
    end
    step(batch);
endtask

// 在采样沿之后选择一个已发送ID返回响应，等真正握手后再暂停后续响应。
// 下一下降沿才应用配置，避免与memory driver在同一个下降沿修改/读取配置产生竞争。
task wbb_scenario_sequence::release_response(int id);
    int target;

    obs.wait_cycles(1);
    target = obs.response_count + 1;
    cfg.mem_response_order = WBB_MEM_SELECTED;
    cfg.mem_selected_response_id = id;
    cfg.mem_response_enable = 1;
    obs.wait_for_responses(target);
    cfg.mem_response_enable = 0;
endtask

// 查询同址、异址、左边命中、右边命中和双不命中；输出正确性由现有模型及断言检查。
task wbb_scenario_sequence::query_pairs(bit [ADDR_WIDTH-1:0] a, bit [ADDR_WIDTH-1:0] b,
    bit [ADDR_WIDTH-1:0] miss);
    query(a, a);
    query(a, b);
    query(b, a);
    query(a, miss);
    query(miss, a);
    query(miss, miss);
endtask

// 返回本场景已准备的写回事务数量，查询和空闲操作不计入其中。
function int wbb_scenario_sequence::get_record_count();
    return records.size();
endfunction

// 返回原始地址/数据的副本，供base test统一执行C++内存回读比较。
function wbb_scenario_sequence::writeback_record_t wbb_scenario_sequence::get_record(int index);
    if (index < 0 || index >= records.size()) begin
        `fatal("Scenario record index is out of range", "WBB_SEQUENCE_RECORD")
    end
    return records[index];
endfunction
