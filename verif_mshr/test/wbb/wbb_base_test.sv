class wbb_base_test extends uvm_test;
    typedef struct packed {
        int reserve_count;
        int push_count;
        int send_count;
        int response_count;
    } writeback_counts_t;

    wbb_environment env;
    virtual wbb_interface vif;
    wbb_config cfg;
    // TB 顶层传入的时钟配置；派生 test 读取它计算等待时间，不另建时钟配置。
    protected clk_rst_config clk_cfg;
    protected bit supports_input_modes = 0;
    protected wbb_input_mode_t fixed_input_mode = WBB_INPUT_SERIAL;

    `uvm_component_utils(wbb_base_test)

    function new(string name = "wbb_base_test",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (get_parent() == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern virtual function void report_phase(uvm_phase phase);
    extern function void require_active_agent();
    extern task wait_for_drain();
    extern function writeback_counts_t get_writeback_counts();
    extern function void check_writeback_counts(int expected_count, writeback_counts_t before_counts = '0);
    extern function void check_count(string name, int actual_count, int expected_count, bit at_least = 0);
    extern function bit check_memory_line(bit [ADDR_WIDTH-1:0] addr, bit [LINE_WIDTH-1:0] expected_data,
        string label = "writeback", bit fatal_on_mismatch = 0);
    extern task run_scenario(wbb_scenario_sequence seq, int expected_count);
    extern function void check_scenario_data(wbb_scenario_sequence seq);
    extern function void configure_input_mode();
    extern function string input_mode_name();
    extern function void check_input_mode_coverage(int overlap_before);
    extern function void check_scenario_inputs(wbb_scenario_sequence seq, writeback_counts_t before_counts);

endclass

function void wbb_base_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clk_cfg) || clk_cfg == null) begin
        `fatal("TB top must provide a non-null clk_rst_config to the test", "CLK_CONFIG")
    end
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg)) begin
        cfg = wbb_config::type_id::create("cfg");
    end
    configure_input_mode();
    uvm_config_db #(wbb_config)::set(this, "env", "wbb_config", cfg);
    uvm_config_db #(clk_rst_config)::set(this, "env", "clk_rst_config", clk_cfg);
    env = wbb_environment::type_id::create("env", this);
endfunction

task wbb_base_test::run_phase(uvm_phase phase);
    int overlap_before;

    phase.raise_objection(this);
    fork
        begin
            wait (vif.rst_n === 1'b1);
            repeat (2) @(negedge vif.clk);
            overlap_before = env.activity.overlap_count;
            run_sequence();
            wait_for_drain();
            check_input_mode_coverage(overlap_before);
        end
        begin
            repeat (cfg.timeout_cycles) @(negedge vif.clk);
            `fatal("WBB test watchdog timeout", "WBB_TIMEOUT")
        end
    join_any
    disable fork;
    phase.drop_objection(this);
endtask

// 从case声明或命令行选择上游提交方式。可切换case复用同一套检查；固定模式case拒绝不支持的请求。
// 流水必须使用strict编译配置，不能因为关闭下一拍断言而让流水错误通过。
function void wbb_base_test::configure_input_mode();
    string requested;
    wbb_input_mode_t mode;

    // 【防御性检查】确认调用方提供有效对象，避免空句柄被继续访问。
    if (cfg == null) begin
        `fatal("wbb_config cannot be null", "WBB_INPUT_MODE")
    end

    // 先取test支持的默认模式，再处理命令行覆盖。
    mode = supports_input_modes ? cfg.input_mode : fixed_input_mode;
    // 【防御性检查】解析并校验外部指定的模式，非法选项属于环境调用错误。
    if ($value$plusargs("WBB_INPUT_MODE=%s", requested)) begin
        requested = requested.tolower();
        case (requested)
            "serial": mode = WBB_INPUT_SERIAL;
            "pipeline": mode = WBB_INPUT_PIPELINE;
            default: begin
                `fatal("WBB_INPUT_MODE must be serial or pipeline", "WBB_INPUT_MODE")
            end
        endcase
    end

    // 拒绝不支持的模式；流水还需要足够槽位及严格下一拍编译配置。
    // 【防御性检查】所选模式必须在当前test声明的支持范围内。
    if ($isunknown(mode) || !(mode inside {WBB_INPUT_SERIAL, WBB_INPUT_PIPELINE}) ||
        (!supports_input_modes && mode != fixed_input_mode)) begin
        `fatal("Requested input mode is not supported by this test", "WBB_INPUT_MODE")
    end
    cfg.input_mode = mode;
    if (mode == WBB_INPUT_PIPELINE) begin
        // 【防御性检查】确认当前容量足以构造本场景，不代表DUT功能结果检查。
        if (WBB_ENTRIES < 2) begin
            `fatal("Pipelined input requires at least two WBB entries", "WBB_INPUT_MODE")
        end
`ifdef WBB_ALLOW_DELAYED_PUSH
        `fatal("Pipelined input requires the strict next-cycle-push build", "WBB_INPUT_MODE")
`endif
    end

    // 记录最终模式，供回归核对实际运行是否符合请求。
    `info($sformatf("input_mode=%s", input_mode_name()), "WBB_INPUT_MODE")
endfunction

// 返回便于日志和报告使用的输入模式名称，不改变配置。
function string wbb_base_test::input_mode_name();
    return cfg.input_mode == WBB_INPUT_PIPELINE ? "pipeline" : "serial";
endfunction

// 用实际握手验证模式已经生效：串行不应重叠，流水至少出现一次，并且不允许延迟push。
function void wbb_base_test::check_input_mode_coverage(int overlap_before);
    int overlaps;

    overlaps = env.activity.overlap_count - overlap_before;
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        check_count("pipelined input overlap", overlaps, 1, 1);
        check_count("pipelined input delayed pushes", env.activity.delayed_push_count, 0);
    end else begin
        check_count("serial input overlap", overlaps, 0);
    end
    `info($sformatf("input_mode=%s overlaps=%0d", input_mode_name(), overlaps), "WBB_INPUT_MODE_COVERAGE")
endfunction

// 启动基础sequence的两笔写回，再用公共工具等待响应和检查计数；地址/数据由sequence生成。
// 等待过程由 run_phase 的总 watchdog 保护，派生 test 可以覆盖本 task 组织其他场景。
task wbb_base_test::run_sequence();
    wbb_smoke_sequence seq;
    writeback_counts_t before_counts;

    require_active_agent();
    before_counts = get_writeback_counts();

    seq = wbb_smoke_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);

    wait_for_drain();
    check_writeback_counts(2, before_counts);
endtask

// 在启动激励前确认上游 agent 有 sequencer，配置成 passive 时给出明确错误。
function void wbb_base_test::require_active_agent();
    // 【防御性检查】有激励的test需要active agent及sequencer，避免在passive配置下启动。
    if (env.agent.sequencer == null) begin
        `fatal("Writeback stimulus requires an active WBB agent", "WBB_NO_SEQUENCER")
    end
endfunction

// sequence 返回只表示 reserve/push 完成；先等待4个下降沿，再等待剩余发送和响应结束。
// env.is_idle() 内部通过 DPI 查询 C++ WBB 模型，并检查 SV 内存 driver 的待响应记录。
// 调用方应先停止提交新事务；整个等待仍由 run_phase 的总超时保护。
task wbb_base_test::wait_for_drain();
    repeat (4) @(negedge vif.clk);
    while (!env.is_idle()) begin
        @(negedge vif.clk);
    end
endtask

// 保存当前四类事件计数；多阶段 case 可在某阶段开始前记录它，之后只检查该阶段新增的事务。
function wbb_base_test::writeback_counts_t wbb_base_test::get_writeback_counts();
    writeback_counts_t counts;

    counts.reserve_count = env.scoreboard.reserve_count;
    counts.push_count = env.scoreboard.push_count;
    counts.send_count = env.scoreboard.send_count;
    counts.response_count = env.scoreboard.response_count;
    return counts;
endfunction

// 检查 reserve 成功、push、send 握手和响应握手是否都完成规定笔数。
// 不传 before_counts 时检查总数；传入开始前的计数时，检查此后增加的笔数。
function void wbb_base_test::check_writeback_counts(int expected_count, writeback_counts_t before_counts);
    writeback_counts_t counts;

    counts = get_writeback_counts();
    check_count("reserve", counts.reserve_count - before_counts.reserve_count, expected_count);
    check_count("push", counts.push_count - before_counts.push_count, expected_count);
    check_count("send", counts.send_count - before_counts.send_count, expected_count);
    check_count("response", counts.response_count - before_counts.response_count, expected_count);
endfunction

// 通用计数检查：默认要求实际值恰好等于期望值；at_least=1 时要求至少达到期望值。
// 不满足时打印具体计数名称、实际值和要求；未知值或负的期望值也明确报错。
function void wbb_base_test::check_count(string name, int actual_count, int expected_count, bit at_least);
    if ($isunknown({actual_count, expected_count}) || expected_count < 0 ||
        (at_least ? actual_count < expected_count : actual_count !== expected_count)) begin
        `error($sformatf("%s: actual=%0d required%s%0d", name, actual_count,
            at_least ? ">=" : "=", expected_count), "WBB_TEST_COUNT")
    end
endfunction

// 读取指定地址的一整行内存，与调用方提供的原始数据比较，返回1表示相同。
// label 说明正在检查哪笔数据；准备阶段必须成功时，可将 fatal_on_mismatch 设为1。
function bit wbb_base_test::check_memory_line(bit [ADDR_WIDTH-1:0] addr, bit [LINE_WIDTH-1:0] expected_data,
    string label, bit fatal_on_mismatch);
    bit [LINE_WIDTH-1:0] actual_data;
    string message;

    // read_actual() 定义在 src/wbb/model/wbb_memory_store.sv，内部经 sparse_mem_read_line DPI
    // 读取 RefModel/MEM/SparseMemory.hpp 的 C++ 内存对象，内容来自 DUT 已握手的 send 数据。
    env.memory.read_actual(addr, actual_data);
    if (actual_data === expected_data) begin
        return 1;
    end
    message = $sformatf("%s mismatch at 0x%h: expected=%h actual=%h", label, addr, expected_data, actual_data);
    if (fatal_on_mismatch) begin
        `fatal(message, "WBB_TEST_MEMORY")
    end else begin
        `error(message, "WBB_TEST_MEMORY")
    end
    return 0;
endfunction

// 多阶段case共用的启动和收尾：检查N笔完整写回、等待响应、核对最终内存数据。
// 具体场景必须自行放行暂停的内存请求/响应；这里不会替case修改控制策略。
task wbb_base_test::run_scenario(wbb_scenario_sequence seq, int expected_count);
    writeback_counts_t before_counts;

    require_active_agent();
    // 【防御性检查】确认调用方提供有效对象，避免空句柄被继续访问。
    if (seq == null) begin
        `fatal("Scenario sequence cannot be null", "WBB_SEQUENCE_CONFIG")
    end
    before_counts = get_writeback_counts();
    seq.start(env.agent.sequencer);
    wait_for_drain();
    check_count("scenario generated writebacks", seq.get_record_count(), expected_count);
    check_writeback_counts(expected_count, before_counts);
    check_scenario_inputs(seq, before_counts);
    check_scenario_data(seq);
endtask

// 逐笔比较实际reserve/push输入与sequence保存的原始数据，检查driver没有串错地址、槽号或数据。
// 即使旧地址后来被覆盖，这个检查也保留每一次写回的输入版本；DUT行为仍由C++模型和SVA检查。
function void wbb_base_test::check_scenario_inputs(wbb_scenario_sequence seq, writeback_counts_t before_counts);
    wbb_scenario_sequence::writeback_record_t record;
    wbb_sample reserved;
    wbb_sample pushed;
    int reserve_index;
    int push_index;

    // 先确认采样数量完整，再逐笔访问reserve/push历史。
    if (env.activity.reserve_samples.size() < before_counts.reserve_count + seq.get_record_count() ||
        env.activity.push_samples.size() < before_counts.push_count + seq.get_record_count()) begin
        `error("Original writebacks do not have complete reserve/push input records", "WBB_STIMULUS_RECORDS")
        return;
    end

    // 按原始激励顺序核对地址、槽号与数据；流水额外检查间隔严格为1拍。
    for (int index = 0; index < seq.get_record_count(); index++) begin
        reserve_index = before_counts.reserve_count + index;
        push_index = before_counts.push_count + index;
        reserved = env.activity.reserve_samples[reserve_index];
        pushed = env.activity.push_samples[push_index];
        record = seq.get_record(index);
        if (reserved.reserve_addr !== record.addr || pushed.push_slot !== reserved.reserveSlot ||
            pushed.push_line !== record.line_data) begin
            `error($sformatf("Writeback %0d input address/slot/data differs from the original item", index),
                "WBB_STIMULUS_DATA")
        end
        if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
            check_count($sformatf("writeback %0d reserve-to-push cycles", index),
                int'(env.activity.push_cycles[push_index] - env.activity.reserve_cycles[reserve_index]), 1);
        end
    end
endfunction

// 同一地址可在响应完成后再次写入；最终内存比较使用该地址最后一次准备的数据。
// 更早版本在每次send时仍由C++ WBB模型和IO断言检查，不能用最后一版替代逐次比较。
function void wbb_base_test::check_scenario_data(wbb_scenario_sequence seq);
    wbb_scenario_sequence::writeback_record_t record;
    bit [LINE_WIDTH-1:0] latest[bit [ADDR_WIDTH-1:0]];

    for (int index = 0; index < seq.get_record_count(); index++) begin
        record = seq.get_record(index);
        latest[record.addr] = record.line_data;
    end
    foreach (latest[addr]) begin
        // check_memory_line内部经DPI读取C++ SparseMemory；场景sequence本身不访问模型。
        void'(check_memory_line(addr, latest[addr], "scenario final data"));
    end
endfunction

function void wbb_base_test::report_phase(uvm_phase phase);
    uvm_report_server server;
    super.report_phase(phase);
    server = uvm_report_server::get_server();
    if (server.get_severity_count(UVM_ERROR) == 0 && server.get_severity_count(UVM_FATAL) == 0) begin
        `info("WBB test completed with C++ reference and backing-memory checks", "WBB_TEST_PASS")
    end else begin
        `info("WBB test failed; inspect UVM_ERROR/UVM_FATAL", "WBB_TEST_FAIL")
    end
endfunction
