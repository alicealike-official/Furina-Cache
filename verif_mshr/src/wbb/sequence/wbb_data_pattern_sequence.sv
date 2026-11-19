// 为 WBB 写回测试生成不同取值的整行数据，并通过完整事务发送给 driver。
// pattern 指“数据模式”，说明一行数据中各个位、字节和字分别取什么值；下面列出九种模式。
class wbb_data_pattern_sequence extends wbb_base_sequence;
    typedef enum int {
        ALL_ZERO,           // 整行每一位都是0。
        ALL_ONE,            // 整行每一位都是1。
        WORD_INCREMENT,     // 第0个字为1，第1个字为2，后面的字依次加1。
        BYTE_INCREMENT,     // 第0个字节为1，第1个字节为2，后面的字节依次加1，取低8位。
        ALTERNATING_ONE,    // 每个字节都是 0xAA，即二进制10101010。
        ALTERNATING_ZERO,   // 每个字节都是 0x55，即二进制01010101。
        WALKING_ONE,        // 每笔只有一位为1，其余为0；这个1的位置逐笔改变。
        WALKING_ZERO,       // 每笔只有一位为0，其余为1；这个0的位置逐笔改变。
        RANDOM_LINE         // 随机产生整行每一位的值。
    } pattern_kind_t;

    // 保存一笔测试数据的类型、地址和整行内容，供 test 最后读取内存时比较。
    typedef struct packed {
        pattern_kind_t kind;
        bit [ADDR_WIDTH-1:0] addr;
        bit [LINE_WIDTH-1:0] line_data;
    } pattern_record_t;

    localparam int RANDOM_LINE_COUNT = 32;
    localparam int PATTERN_KIND_COUNT = 9;
    // 六种固定数据 + 每一位上的单个1/0 + 随机数据；额外的全1准备写回另加1笔。
    localparam int EXPECTED_PATTERNS = 6 + 2 * LINE_WIDTH + RANDOM_LINE_COUNT;
    localparam int EXPECTED_WRITEBACKS = EXPECTED_PATTERNS + 1;

    // 为1时只执行最开始的全1准备写回；为0时执行全部九种数据模式。
    bit preload_only = 0;
    protected pattern_record_t records[$];

    `uvm_object_utils(wbb_data_pattern_sequence)

    function new(string name = "wbb_data_pattern_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task send_preload();
    extern task send_pattern(pattern_kind_t kind, bit [LINE_WIDTH-1:0] line_data);
    extern task send_fixed_patterns();
    extern task send_walking_patterns();
    extern task send_random_patterns();
    extern function int get_record_count();
    extern function pattern_record_t get_record(int index);

endclass

task wbb_data_pattern_sequence::body();
    if (DATA_WIDTH % 8 != 0 || LINE_WIDTH != WORDS_PER_BLOCK * DATA_WIDTH ||
        LINE_WIDTH != BLOCK_SIZE * 8) begin
        `fatal("Data patterns require consistent byte, word and line widths", "WBB_PATTERN_CONFIG")
    end
    records.delete();

    // test 先启动一次全1准备写回，等响应并读取内存确认成功后，再启动全部数据模式。
    if (preload_only) begin
        send_preload();
    end else begin
        send_fixed_patterns();
        send_walking_patterns();
        send_random_patterns();
    end
endtask

// 先向地址 BLOCK_SIZE 写一整行全1数据，后面的全0测试会写入同一个地址。
// 最后读到全0，才能说明原先的全1数据被正确覆盖；不会把未写过的内存默认值当成测试结果。
// 本 task 返回时只完成 reserve/push；等待内存响应和检查全1写入结果由 test 负责。
task wbb_data_pattern_sequence::send_preload();
    writeback_line(ADDR_WIDTH'(BLOCK_SIZE), '1, ADDR_WIDTH'(BLOCK_SIZE), '0);
endtask

// 为当前数据选择一个按块大小对齐的地址，保存地址和数据，再提交一笔完整写回事务。
// 测试地址依次为 BLOCK_SIZE、2*BLOCK_SIZE 等，避免后面的测试数据覆盖前面的结果。
// 地址0只用于查询，不写入；计算出的地址若超过地址位宽后变成0或小于等于前一个地址，就报错。
// 保存的是地址和数据本身，driver 后续修改 transaction 对象不会改变这里的记录。
task wbb_data_pattern_sequence::send_pattern(pattern_kind_t kind, bit [LINE_WIDTH-1:0] line_data);
    pattern_record_t record;

    record.kind = kind;
    record.addr = ADDR_WIDTH'((records.size() + 1) * BLOCK_SIZE);
    record.line_data = line_data;
    if (record.addr == '0) begin
        `fatal("Data pattern addresses exceed the available address space", "WBB_PATTERN_ADDR")
    end
    if (records.size() > 0 && record.addr <= records[$].addr) begin
        `fatal("Data pattern addresses wrap or repeat", "WBB_PATTERN_ADDR")
    end
    records.push_back(record);
    writeback_line(record.addr, line_data, record.addr, '0);
endtask

// 发送六笔固定数据：全0、全1、各字依次为1/2/3、各字节依次为1/2/3，以及每字节为AA和55。
// word0 放在整行最低 DATA_WIDTH 位，byte0 放在最低8位。
// 不同位置使用不同的值，可以检查字或字节是否被调换；全0/全1/AA/55用于检查各位的数据。
task wbb_data_pattern_sequence::send_fixed_patterns();
    bit [LINE_WIDTH-1:0] line_data;

    send_pattern(ALL_ZERO, '0);
    send_pattern(ALL_ONE, '1);

    for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
        line_data[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(word_index + 1);
    end
    send_pattern(WORD_INCREMENT, line_data);

    for (int byte_index = 0; byte_index < BLOCK_SIZE; byte_index++) begin
        line_data[byte_index * 8 +: 8] = 8'(byte_index + 1);
    end
    send_pattern(BYTE_INCREMENT, line_data);

    for (int bit_index = 0; bit_index < LINE_WIDTH; bit_index++) begin
        line_data[bit_index] = bit'(bit_index % 2);
    end
    send_pattern(ALTERNATING_ONE, line_data);
    send_pattern(ALTERNATING_ZERO, ~line_data);
endtask

// walking-1：整行只有第 bit_index 位为1，其余位为0；每次循环把这个1移到下一位。
// walking-0：把上述数据全部取反，只有第 bit_index 位为0，其余位为1。
// 每个位都发送这两笔数据，用于检查该位是否丢失或被放到错误的位置；512位行共发送1024笔。
// 每笔事务仍通过一次 push 提交完整行数据。
task wbb_data_pattern_sequence::send_walking_patterns();
    bit [LINE_WIDTH-1:0] line_data;

    for (int bit_index = 0; bit_index < LINE_WIDTH; bit_index++) begin
        line_data = '0;
        line_data[bit_index] = 1'b1;
        send_pattern(WALKING_ONE, line_data);
        send_pattern(WALKING_ZERO, ~line_data);
    end
endtask

// 随机生成32笔完整的行数据，每一笔都随机化全部 LINE_WIDTH 位，而不是只随机一个字。
// 随机化失败时报 fatal；相同代码和仿真设置下，使用相同 +ntb_random_seed 可以重现数据。
task wbb_data_pattern_sequence::send_random_patterns();
    bit [LINE_WIDTH-1:0] line_data;

    repeat (RANDOM_LINE_COUNT) begin
        if (!std::randomize(line_data)) begin
            `fatal("Failed to randomize a complete cache line", "WBB_PATTERN_RANDOM")
        end
        send_pattern(RANDOM_LINE, line_data);
    end
endtask

// 返回九种数据模式一共生成了多少笔数据，供 test 检查是否少发或多发。
// 最开始为全0测试准备的那笔全1写回不计入这里，但会计入 test 的总事务数量。
function int wbb_data_pattern_sequence::get_record_count();
    return records.size();
endfunction

// 取出第 index 笔测试数据的类型、地址和整行内容，供 test 与内存中读到的结果比较。
// 返回一份数据副本；test 修改副本不会改变这里保存的记录。index 超出范围时报错。
function wbb_data_pattern_sequence::pattern_record_t wbb_data_pattern_sequence::get_record(int index);
    if (index < 0 || index >= records.size()) begin
        `fatal($sformatf("Invalid pattern record index %0d (size=%0d)",
            index, records.size()), "WBB_PATTERN_RECORD")
    end
    return records[index];
endfunction
