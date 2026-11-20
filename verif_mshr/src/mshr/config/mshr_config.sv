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
    bit fill_enable = 1;
    bit replay_enable = 1;

    `uvm_object_utils(mshr_config)

    function new(string name = "mshr_config");
        super.new(name);
    endfunction

endclass
