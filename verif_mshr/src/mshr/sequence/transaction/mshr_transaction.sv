typedef enum int {
    MSHR_ALLOC,
    MSHR_MERGE,
    MSHR_QUERY,
    MSHR_IDLE
} mshr_operation_t;

class mshr_transaction extends uvm_sequence_item;
    // TB复位边界专用：从已确认的空态直接提交第一拍alloc，不改变普通事务的查询流程。
    bit reset_release_alloc = 0;
    // ALLOC/MERGE各表示一个Slot请求；返回只代表上游提交，不代表内存或replay完成。
    mshr_operation_t operation = MSHR_ALLOC;
    int unsigned cycles = 1;
    bit idle_payload_enable = 0;
    rand bit [TAG_WIDTH-1:0] tag;
    rand bit [INDEX_WIDTH-1:0] index;
    rand bit [WAY_WIDTH-1:0] way;
    rand bit isWrite;
    rand bit [DATA_WIDTH-1:0] wData;
    rand bit [WORD_OFF_WIDTH-1:0] wordOff;
    rand bit [CPU_ID_WIDTH-1:0] respId;
    rand bit hasWb;
    rand bit [WBB_SLOT_WIDTH-1:0] wbSlot;

    // 真正提交周期的两个独立查询输入；资源等待阶段driver会临时用q1查询请求块。
    rand bit [TAG_WIDTH-1:0] q0Tag;
    rand bit [INDEX_WIDTH-1:0] q0Index;
    rand bit [TAG_WIDTH-1:0] q1Tag;
    rand bit [INDEX_WIDTH-1:0] q1Index;

    // 实际提交位置由driver根据沿前freeEntry或查询结果反馈，不是DUT新增的accepted信号。
    bit [ENTRY_WIDTH-1:0] entry;
    int selected_entry = -1;
    int selected_slot = -1;

    constraint legal_fields {
        index < NUM_SETS;
        way < NUM_WAYS;
        wordOff < WORDS_PER_BLOCK;
        wbSlot < WBB_ENTRIES;
        q0Index < NUM_SETS;
        q1Index < NUM_SETS;
    }

    `uvm_object_utils_begin(mshr_transaction)
        `uvm_field_enum(mshr_operation_t, operation, UVM_DEFAULT)
        `uvm_field_int(cycles, UVM_DEFAULT)
        `uvm_field_int(idle_payload_enable, UVM_DEFAULT)
        `uvm_field_int(tag, UVM_DEFAULT)
        `uvm_field_int(index, UVM_DEFAULT)
        `uvm_field_int(way, UVM_DEFAULT)
        `uvm_field_int(isWrite, UVM_DEFAULT)
        `uvm_field_int(wData, UVM_DEFAULT)
        `uvm_field_int(wordOff, UVM_DEFAULT)
        `uvm_field_int(respId, UVM_DEFAULT)
        `uvm_field_int(hasWb, UVM_DEFAULT)
        `uvm_field_int(wbSlot, UVM_DEFAULT)
        `uvm_field_int(q0Tag, UVM_DEFAULT)
        `uvm_field_int(q0Index, UVM_DEFAULT)
        `uvm_field_int(q1Tag, UVM_DEFAULT)
        `uvm_field_int(q1Index, UVM_DEFAULT)
        `uvm_field_int(entry, UVM_DEFAULT)
        `uvm_field_int(selected_entry, UVM_DEFAULT)
        `uvm_field_int(selected_slot, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "mshr_transaction");
        super.new(name);
    endfunction

endclass
