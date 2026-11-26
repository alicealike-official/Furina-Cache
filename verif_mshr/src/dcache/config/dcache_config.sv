class dcache_config extends uvm_object;
    // 复位台架选项：清理本地义务并使外部旧调度静默，不定义系统迟到响应处理规则。
    bit allow_reset_cancellation = 0;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit continuous_cpu = 0;
    bit enable_probes = 1;
    longint unsigned read_response_not_before_cycle = 0;
    int timeout_cycles = 10000;
    int request_timeout_cycles = 1000;
    int read_latency_cycles = 2;
    int write_latency_cycles = 2;
    // 响应策略只影响尚未呈现的队列项，0=FIFO、1=逆序、2=随机。
    int response_order = 0;
    bit random_memory_ready = 0;
    bit random_memory_latency = 0;
    int ready_percent = 65;
    int max_latency_cycles = 32;
    bit [3:0] idle_response_id = 0;
    bit [511:0] idle_response_data = 0;
    bit read_request_enable = 1;
    bit write_request_enable = 1;
    bit read_response_enable = 1;
    bit write_response_enable = 1;
    bit random_cpu_ready = 0;
    int cpu_ready_percent = 70;
    int cpu_max_stall_cycles = 16;
    longint unsigned write_response_not_before_cycle = 0;
    bit cpu_read_ready = 1;
    bit cpu_write_ready = 1;
    `uvm_object_utils(dcache_config)
    function new(string name = "dcache_config");
        super.new(name);
    endfunction
endclass
