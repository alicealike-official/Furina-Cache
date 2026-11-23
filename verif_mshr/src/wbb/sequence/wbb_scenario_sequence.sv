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
    extern task send_group(wbb_transaction items[$]);
    extern task send_batch(int first_index, int hold_cycles,
        bit [ADDR_WIDTH-1:0] q0 = '0, bit [ADDR_WIDTH-1:0] q1 = '0);
    extern function wbb_batch_transaction make_batch(int first_index, int count, wbb_batch_mode_t mode,
        bit [ADDR_WIDTH-1:0] q0 = '0, bit [ADDR_WIDTH-1:0] q1 = '0);
    extern task send_pipeline_batch(int first_index, int count);
    extern task release_response(int id);
    extern task query_pairs(bit [ADDR_WIDTH-1:0] first_addr, bit [ADDR_WIDTH-1:0] last_addr,
        bit [ADDR_WIDTH-1:0] miss_addr);
    extern function int get_record_count();
    extern function writeback_record_t get_record(int index);
endclass

task wbb_scenario_sequence::pre_body();
    wbb_sequencer sequencer;

    super.pre_body();
    // 【防御性检查】确认sequence运行在配套sequencer上，才能取得配置和观测接口。
    if (!$cast(sequencer, get_sequencer())) begin
        `fatal("Scenario sequence requires wbb_sequencer", "WBB_SEQUENCE_CONFIG")
    end
    cfg = sequencer.cfg;
    obs = sequencer.observations;
    records.delete();
endtask

// 按编号生成非零块地址，遇到负编号或地址溢出时明确报错。
function bit [ADDR_WIDTH-1:0] wbb_scenario_sequence::block_addr(int index);
    longint unsigned block_address;

    block_address = (64'(index) + 1) * BLOCK_SIZE;
    // 【防御性检查】防止调用方编号非法或地址计算溢出，避免生成错误激励。
    if (index < 0 || block_address == 0 || 64'(ADDR_WIDTH'(block_address)) != block_address) begin
        `fatal("Scenario block address is out of range", "WBB_SEQUENCE_ADDRESS")
    end
    return ADDR_WIDTH'(block_address);
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

// 保存一组原始地址和数据，再由base sequence按配置选择串行或流水提交。
// 具体的数据与查询组合由各case生成；响应完成后的地址复用仍由场景控制。
task wbb_scenario_sequence::send_group(wbb_transaction items[$]);
    writeback_record_t record;

    // 保存原始激励，供test在提交结束后逐笔检查地址、数据及最终内存内容。
    foreach (items[index]) begin
        // 【防御性检查】批次中的每项都必须是已创建的事务对象。
        if (items[index] == null) begin
            `fatal("Scenario group contains a null writeback", "WBB_SEQUENCE_GROUP")
        end
        record.addr = items[index].addr;
        record.line_data = items[index].line_data;
        records.push_back(record);
    end

    // 由base sequence选择串行或流水提交，避免各场景重复实现批次调度。
    submit_writebacks(items, cfg.input_mode);
endtask

// 提交包含N笔完整写回的批次，先全部预留，再等待指定拍数，最后逐笔push。
// 该操作仅用于显式延迟模式；它不产生reserve和push同拍。
task wbb_scenario_sequence::send_batch(int first_index, int hold_cycles,
    bit [ADDR_WIDTH-1:0] q0, bit [ADDR_WIDTH-1:0] q1);
    wbb_batch_transaction batch;

    batch = make_batch(first_index, WBB_ENTRIES, WBB_BATCH_DEFERRED, q0, q1);
    batch.hold_cycles = hold_cycles;
    step(batch);
endtask

// 统一生成一批完整写回并保存原始数据；默认延迟批次的查询规则保持原样。
// 流水批次在reserve第i笔时查询上一笔地址和自身地址；首笔的q0查未使用的地址0。
function wbb_batch_transaction wbb_scenario_sequence::make_batch(int first_index, int count,
    wbb_batch_mode_t mode, bit [ADDR_WIDTH-1:0] q0, bit [ADDR_WIDTH-1:0] q1);
    wbb_batch_transaction batch;
    writeback_record_t record;

    // 检查批次数量，再设置整批的调度方式与查询参数。
    // 【防御性检查】批次生成接口需要正的事务数量。
    if (count <= 0) begin
        `fatal("A writeback batch must contain at least one entry", "WBB_SEQUENCE_BATCH")
    end
    batch = wbb_batch_transaction::type_id::create("batch");
    batch.mode = mode;
    batch.q0Addr = q0;
    batch.q1Addr = q1;
    if (mode == WBB_BATCH_PIPELINED) begin
        batch.hold_cycles = 0;
    end

    for (int index = 0; index < count; index++) begin
        wbb_transaction item;

        // 每笔写回使用自己的块地址和数据；普通批次查询本笔地址。
        item = wbb_transaction::type_id::create($sformatf("entry_%0d", index));
        item.addr = block_addr(first_index + index);
        item.line_data = make_line(first_index + index);
        item.q0Addr = item.addr;
        item.q1Addr = q1;

        // 流水批次同时查询上一笔预留地址和本笔地址，观察两个阶段的交接。
        if (mode == WBB_BATCH_PIPELINED) begin
            item.q0Addr = index == 0 ? '0 : block_addr(first_index + index - 1);
            item.q1Addr = item.addr;
        end

        // 将事务加入批次，并保存不依赖事务句柄后续修改的原始数据副本。
        batch.entries.push_back(item);
        record.addr = item.addr;
        record.line_data = item.line_data;
        records.push_back(record);
    end

    return batch;
endfunction

// 以严格下一拍push方式提交流水批次；批内可以超过槽数，由driver在满槽时等待。
// step返回前必须完成最后一笔push，内存响应仍由场景和base test等待。
task wbb_scenario_sequence::send_pipeline_batch(int first_index, int count);
    wbb_batch_transaction batch;

    batch = make_batch(first_index, count, WBB_BATCH_PIPELINED);
    step(batch);
endtask

// 在采样沿之后选择一个已发送ID返回响应，等真正握手后再暂停后续响应。
// 下一下降沿才应用配置，避免与memory driver在同一个下降沿修改/读取配置产生竞争。
task wbb_scenario_sequence::release_response(int id);
    int response_target;

    // 在采样后选择要返回的已发送ID，并记录此次响应的累计计数目标。
    obs.wait_cycles(1);
    response_target = obs.response_count + 1;
    cfg.mem_response_order = WBB_MEM_SELECTED;
    cfg.mem_selected_response_id = id;
    cfg.mem_response_enable = 1;

    // 等到实际响应握手再关闭放行，不能只因已设置valid就认为响应完成。
    obs.wait_for_responses(response_target);
    cfg.mem_response_enable = 0;
endtask

// 对本轮首尾写回地址和未占用地址执行六种查询组合；输出正确性由模型及断言检查。
// 首尾地址占用时应命中，释放后重复执行这些查询时应不命中，方法自身不固定期望值。
task wbb_scenario_sequence::query_pairs(bit [ADDR_WIDTH-1:0] first_addr, bit [ADDR_WIDTH-1:0] last_addr,
    bit [ADDR_WIDTH-1:0] miss_addr);
    // 两口查询同一个写回地址。
    query(first_addr, first_addr);

    // 两口查询不同写回地址，并交换查询口，检查两路独立性。
    query(first_addr, last_addr);
    query(last_addr, first_addr);

    // 一个口查写回地址，另一个口查未占用地址，再交换两口。
    query(first_addr, miss_addr);
    query(miss_addr, first_addr);

    // 两口都查询未占用地址。
    query(miss_addr, miss_addr);
endtask

// 返回本场景已准备的写回事务数量，查询和空闲操作不计入其中。
function int wbb_scenario_sequence::get_record_count();
    return records.size();
endfunction

// 返回原始地址/数据的副本，供base test统一执行C++内存回读比较。
function wbb_scenario_sequence::writeback_record_t wbb_scenario_sequence::get_record(int index);
    // 【防御性检查】检查调用方索引是否落在已保存的激励记录范围内。
    if (index < 0 || index >= records.size()) begin
        `fatal("Scenario record index is out of range", "WBB_SEQUENCE_RECORD")
    end
    return records[index];
endfunction
