class mshr_smoke_sequence extends mshr_base_sequence;
    protected bit [LINE_WIDTH-1:0] initial_lines[2];
    protected bit prepared;

    `uvm_object_utils(mshr_smoke_sequence)

    function new(string name = "mshr_smoke_sequence");
        super.new(name);
    endfunction

    extern function void prepare();
    extern function bit [ADDR_WIDTH-1:0] block_address(int index);
    extern function bit [LINE_WIDTH-1:0] initial_line(int index);
    extern function bit [LINE_WIDTH-1:0] expected_fill(int index);
    extern task submit_request(int index);
    extern virtual task body();
endclass

// 准备两条逐字不同的外部内存行。数据由sequence生成，test只负责交给MEM封装预置。
function void mshr_smoke_sequence::prepare();
    for (int line_index = 0; line_index < 2; line_index++) begin
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            initial_lines[line_index][word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('h10000000 + line_index * 'h10000 + word_index);
        end
    end
    prepared = 1;
endfunction

// 返回该笔请求的块地址；默认配置使用不同set，避免两个Entry争同一set/way。
function bit [ADDR_WIDTH-1:0] mshr_smoke_sequence::block_address(int index);
    // 【防御性检查】检查基础激励是否已准备，以及调用方使用的行索引是否合法。
    if (index < 0 || index >= 2) begin
        `fatal("Smoke line index out of range", "MSHR_SMOKE")
    end
    return ADDR_WIDTH'((index + 1) * BLOCK_SIZE);
endfunction

// 返回外部MEM的原始行副本，调用者不能通过它修改sequence中的期望记录。
function bit [LINE_WIDTH-1:0] mshr_smoke_sequence::initial_line(int index);
    // 【防御性检查】检查基础激励是否已准备，以及调用方使用的行索引是否合法。
    if (!prepared || index < 0 || index >= 2) begin
        `fatal("Smoke data is not prepared or index invalid", "MSHR_SMOKE")
    end
    return initial_lines[index];
endfunction

// 读未命中填充原始行；写未命中只覆盖末字，其余字仍来自请求时的MEM快照。
function bit [LINE_WIDTH-1:0] mshr_smoke_sequence::expected_fill(int index);
    bit [LINE_WIDTH-1:0] fill_data;
    fill_data = initial_line(index);
    if (index == 1) begin
        fill_data[(WORDS_PER_BLOCK - 1) * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('hdeadbeef);
    end
    return fill_data;
endfunction

// 提交一笔完整的上游Slot请求，第一笔读首字，第二笔写末字；不在test中生成激励字段。
task mshr_smoke_sequence::submit_request(int index);
    mshr_transaction item;
    bit [ADDR_WIDTH-1:0] addr;
    addr = block_address(index);
    item = mshr_transaction::type_id::create($sformatf("request_%0d", index));
    item.operation = MSHR_ALLOC;
    item.tag = TAG_WIDTH'(addr >> ($clog2(BLOCK_SIZE) + INDEX_WIDTH));
    item.index = INDEX_WIDTH'(addr >> $clog2(BLOCK_SIZE));
    item.way = WAY_WIDTH'(index);
    item.isWrite = (index == 1);
    item.wData = DATA_WIDTH'('hdeadbeef);
    item.wordOff = WORD_OFF_WIDTH'(index == 0 ? 0 : WORDS_PER_BLOCK - 1);
    item.respId = index == 0 ? '0 : '1;
    item.q0Tag = item.tag;
    item.q0Index = item.index;
    item.q1Tag = item.tag;
    item.q1Index = item.index;
    step(item);
endtask

task mshr_smoke_sequence::body();
    // 【防御性检查】检查基础激励是否已准备，以及调用方使用的行索引是否合法。
    if (!prepared) begin
        `fatal("Test must prepare and preload smoke memory before starting", "MSHR_SMOKE")
    end
    submit_request(0);
    submit_request(1);
endtask
