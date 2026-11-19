typedef enum int {
    WBB_MEM_FIFO,
    WBB_MEM_LIFO,
    WBB_MEM_RANDOM,
    WBB_MEM_SELECTED
} wbb_mem_order_t;

class wbb_config extends uvm_object;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    int unsigned timeout_cycles = 2000;
    int unsigned reserve_timeout_cycles = 1000;
    int unsigned mem_page_size = 4096;
    // send 在第 k 个采样沿握手后，响应最早在第 k+L 个采样沿握手；L 至少为1。
    int unsigned mem_write_latency_cycles = 2;
    int unsigned mem_max_pending = WBB_ENTRIES;
    // sequence 修改控制字段后，memory driver 在下一个下降沿准备下一拍的输出。
    bit mem_send_enable = 1;
    bit mem_response_enable = 1;
    bit mem_random_ready = 0;
    int unsigned mem_ready_percent = 70;
    wbb_mem_order_t mem_response_order = WBB_MEM_FIFO;
    int unsigned mem_selected_response_id = 0;
    // 随机延迟只在开关打开时使用，随机结果在请求接受时固定下来，后续不会改变。
    bit mem_random_latency = 0;
    int unsigned mem_min_latency_cycles = 1;
    int unsigned mem_max_latency_cycles = 8;
`ifdef WBB_ALLOW_DELAYED_PUSH
    bit allow_delayed_push = 1;
`else
    bit allow_delayed_push = 0;
`endif
    `uvm_object_utils(wbb_config)

    function new(string name = "wbb_config");
        super.new(name);
    endfunction

endclass
