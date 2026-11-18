class wbb_base_test extends uvm_test;
    wbb_environment env;
    virtual wbb_interface vif;
    wbb_config cfg;

    `uvm_component_utils(wbb_base_test)

    function new(string name = "wbb_base_test",
        uvm_component parent = null);
        super.new(name, parent);
        if (get_parent() == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern virtual function void report_phase(uvm_phase phase);

endclass

function void wbb_base_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg)) begin
        cfg = wbb_config::type_id::create("cfg");
    end
    uvm_config_db #(wbb_config)::set(this, "env", "wbb_config", cfg);
    env = wbb_environment::type_id::create("env", this);
endfunction

task wbb_base_test::run_phase(uvm_phase phase);
    phase.raise_objection(this);
    fork
        begin
            wait (vif.rst_n === 1'b1);
            repeat (2) @(negedge vif.clk);
            run_sequence();
            repeat (4) @(negedge vif.clk);
            while (!env.is_idle()) begin
                @(negedge vif.clk);
            end
        end
        begin
            repeat (cfg.timeout_cycles) @(negedge vif.clk);
            `fatal("WBB test watchdog timeout", "WBB_TIMEOUT")
        end
    join_any
    disable fork;
    phase.drop_objection(this);
endtask

// 使用已有 sequence 辅助接口发送两笔不同块地址的完整写回事务，各字采用可区分的数据。
// q0 查询当前写回地址，q1 查询另一个块；等待模型和内存响应队列排空后核对四类事件计数。
// 等待过程由 run_phase 的总 watchdog 保护，派生 test 可以覆盖本 task 扩展激励。
task wbb_base_test::run_sequence();
    wbb_base_sequence seq;
    bit [ADDR_WIDTH-1:0] addr;
    bit [ADDR_WIDTH-1:0] query_addr;
    bit [LINE_WIDTH-1:0] line_data;
    int reserve_before;
    int push_before;
    int send_before;
    int response_before;

    if (env.agent.sequencer == null) begin
        `fatal("Base stimulus requires an active WBB agent", "WBB_NO_SEQUENCER")
    end

    reserve_before = env.scoreboard.reserve_count;
    push_before = env.scoreboard.push_count;
    send_before = env.scoreboard.send_count;
    response_before = env.scoreboard.response_count;

    seq = wbb_base_sequence::type_id::create("seq");
    seq.set_sequencer(env.agent.sequencer);
    for (int transaction_index = 0; transaction_index < 2; transaction_index++) begin
        addr = ADDR_WIDTH'((transaction_index + 1) * BLOCK_SIZE);
        query_addr = ADDR_WIDTH'((2 - transaction_index) * BLOCK_SIZE);
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            line_data[word_index * DATA_WIDTH +: DATA_WIDTH] =
                DATA_WIDTH'((transaction_index + 1) * 'h10000000 + word_index);
        end
        seq.writeback_line(addr, line_data, addr, query_addr);
    end

    // 给最后一笔已提交数据留出观测时间，并等待真实写响应完成。
    repeat (4) @(negedge vif.clk);
    while (!env.is_idle()) begin
        @(negedge vif.clk);
    end

    if (env.scoreboard.reserve_count - reserve_before != 2 ||
        env.scoreboard.push_count - push_before != 2 ||
        env.scoreboard.send_count - send_before != 2 ||
        env.scoreboard.response_count - response_before != 2) begin
        `error($sformatf("Expected two complete writebacks; reserve=%0d push=%0d send=%0d response=%0d",
            env.scoreboard.reserve_count - reserve_before,
            env.scoreboard.push_count - push_before,
            env.scoreboard.send_count - send_before,
            env.scoreboard.response_count - response_before), "WBB_BASE_COUNT")
    end
endtask

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
