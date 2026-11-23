// 向有 N 个槽的 WBB 连续提交 N+1 笔写回，让最后一笔在没有空槽时等待。
// 每笔使用不同的块地址和数据；响应延迟由 test 配置，reserve/push 时序由 driver 负责。
class wbb_capacity_sequence extends wbb_base_sequence;
    typedef struct packed {
        bit [ADDR_WIDTH-1:0] addr;
        bit [LINE_WIDTH-1:0] line_data;
    } writeback_record_t;

    localparam int WRITEBACK_COUNT = WBB_ENTRIES + 1;
    protected writeback_record_t records[$];

    `uvm_object_utils(wbb_capacity_sequence)

    function new(string name = "wbb_capacity_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern function void prepare_records();
    extern task send_writeback(int index);
    extern function int get_record_count();
    extern function writeback_record_t get_record(int index);

endclass

task wbb_capacity_sequence::body();
    prepare_records();
    for (int index = 0; index < WRITEBACK_COUNT; index++) begin
        send_writeback(index);
    end
endtask

// 准备 N+1 笔互不覆盖的数据，地址依次为 BLOCK_SIZE、2*BLOCK_SIZE 等。
// 每行的高位数值区分不同事务，低位数值区分行内各个字，便于发现数据写错槽或位置。
// 保存的是地址和数据的副本，test 可用它们检查最终内存内容。
function void wbb_capacity_sequence::prepare_records();
    writeback_record_t record;

    records.delete();
    for (int index = 0; index < WRITEBACK_COUNT; index++) begin
        record.addr = ADDR_WIDTH'((index + 1) * BLOCK_SIZE);
        if (record.addr == '0) begin
            `fatal("Capacity test address exceeds the available address space", "WBB_CAPACITY_ADDR")
        end
        if (index > 0 && record.addr <= records[$].addr) begin
            `fatal("Capacity test addresses wrap or repeat", "WBB_CAPACITY_ADDR")
        end
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            record.line_data[word_index * DATA_WIDTH +: DATA_WIDTH] =
                DATA_WIDTH'((index + 1) * 'h10000 + word_index);
        end
        records.push_back(record);
    end
endfunction

// 提交第 index 笔完整写回；WBB 满时，由已有 driver 保持 reserve 请求并等待空槽。
// q0 查询当前要写的地址，q1 查询第一笔地址，供已有模型和断言检查等待期间的地址占用。
task wbb_capacity_sequence::send_writeback(int index);
    writeback_record_t record;

    record = get_record(index);
    writeback_line(record.addr, record.line_data, record.addr, records[0].addr);
endtask

// 返回 sequence 准备的数据笔数，供 test 与规定的 N+1 笔核对。
function int wbb_capacity_sequence::get_record_count();
    return records.size();
endfunction

// 返回第 index 笔的地址和数据副本，供 test 检查请求地址及最终内存数据；越界时报错。
function wbb_capacity_sequence::writeback_record_t wbb_capacity_sequence::get_record(int index);
    // 【防御性检查】检查调用方索引是否落在已保存的激励记录范围内。
    if (index < 0 || index >= records.size()) begin
        `fatal($sformatf("Invalid capacity record index %0d (size=%0d)",
            index, records.size()), "WBB_CAPACITY_RECORD")
    end
    return records[index];
endfunction
