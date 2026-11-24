typedef enum int {
    MSHR_MEM_FIFO,
    MSHR_MEM_REVERSE,
    MSHR_MEM_RANDOM,
    MSHR_MEM_SELECTED
} mshr_mem_order_t;

class mshr_config extends uvm_object;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    int unsigned timeout_cycles = 2000;
    // 上游等待合法Entry/Slot的最多拍数；未获资源时alloc/merge使能一直为0。
    int unsigned request_timeout_cycles = 1000;
    int unsigned mem_page_size = 4096;
    // 从读请求实际握手沿起算，响应最早在第k+L个采样沿被接受，L至少为1。
    int unsigned mem_read_latency_cycles = 2;
    int unsigned mem_max_pending = MSHR_ENTRIES;
    bit mem_request_enable = 1;
    bit mem_response_enable = 1;
    // fill与replay的接收控制彼此独立，默认全部放行。
    mshr_mem_order_t mem_order = MSHR_MEM_FIFO;
    int unsigned selected_response_id = 0;
    // 定向同拍case按IO观察周期安排放行，不改变已呈现响应。
    longint unsigned response_not_before_cycle = 0;
    longint unsigned request_not_before_cycle = 0;
    bit random_request_ready = 0;
    int unsigned request_ready_percent = 65;
    bit random_latency = 0;
    int unsigned min_latency_cycles = 1;
    int unsigned max_latency_cycles = 16;
    bit random_sinks = 0;
    int unsigned sink_ready_percent = 65;
    bit [BUS_ID_WIDTH-1:0] idle_response_id = '0;
    bit [LINE_WIDTH-1:0] idle_response_data = '0;
    bit fill_enable = 1;
    bit replay_enable = 1;

    `uvm_object_utils(mshr_config)

    function new(string name = "mshr_config");
        super.new(name);
    endfunction

endclass
