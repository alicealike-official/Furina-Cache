class dcache_perf_test extends dcache_scenario_test;
    string scenario = "hit_read";
    string submission = "stream";
    int request_count = 1024;
    int requests_per_line = 1;
    `uvm_component_utils(dcache_perf_test)
    function new(string name = "dcache_perf_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.enable_perf = 1;
        cfg.enable_probes = 1;
        cfg.continuous_cpu = 1;
        cfg.random_memory_ready = 0;
        cfg.random_memory_latency = 0;
        cfg.random_cpu_ready = 0;
        cfg.response_order = 0;
        cfg.read_latency_cycles = 8;
        cfg.write_latency_cycles = 8;
        void'($value$plusargs("PERF_SCENARIO=%s", scenario));
        void'($value$plusargs("PERF_SUBMISSION=%s", submission));
        void'($value$plusargs("PERF_REQUESTS=%d", request_count));
        void'($value$plusargs("PERF_GROUP_SIZE=%d", requests_per_line));
        void'($value$plusargs("PERF_READ_LATENCY=%d", cfg.read_latency_cycles));
        void'($value$plusargs("PERF_WRITE_LATENCY=%d", cfg.write_latency_cycles));
        void'($value$plusargs("PERF_RESULT_FILE=%s", cfg.perf_result_file));
        // 【防御性检查】控制参数必须有效，不用非法延迟或提交模式产生好看的统计。
        if (!(submission inside {"serial", "stream"}) || cfg.read_latency_cycles < 1 || cfg.write_latency_cycles < 1) begin
            `fatal("Invalid performance configuration", "DCACHE_PERF_CONFIG")
        end
    endfunction
    // test只配置并启动；地址、数据、预热和请求调度均在独立perf sequence内完成。
    virtual task run_sequence();
        dcache_perf_sequence seq;
        seq = dcache_perf_sequence::type_id::create("seq");
        seq.scenario = scenario;
        seq.serialized = submission == "serial";
        seq.request_count = request_count;
        seq.requests_per_line = requests_per_line;
        run_scenario(seq);
    endtask
endclass
