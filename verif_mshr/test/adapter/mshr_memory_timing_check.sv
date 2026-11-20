// 单独检查真实 memory driver 的响应拍数，不实例化 MSHR DUT。
// 本文件模拟 DUT 的内存读请求和响应 ready，复用 monitor、memory driver 和 C++ 稀疏内存。
package mshr_memory_timing_pkg;
    timeunit 1ns;
    timeprecision 1ps;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import mshr_params_pkg::*;
    import mshr_pkg::*;
    `include "uvm_macros.svh"
    `include "vutils_macros.svh"

    class mshr_memory_timing_test extends uvm_test;
        localparam int EXACT_REQUESTS = 3;
        virtual mshr_interface vif;
        mshr_config cfg;
        clk_rst_config clock_cfg;
        mshr_monitor monitor;
        mshr_memory_driver memory_driver;
        // C++ SparseMemory 的 SV 封装，定义在 src/mshr/model/mshr_memory_store.sv。
        mshr_memory_store memory;
        uvm_analysis_imp #(mshr_sample, mshr_memory_timing_test) sample_export;
        protected longint unsigned sample_cycle = 0;
        protected longint unsigned accepted_at[int unsigned];
        protected bit exact_response[int unsigned];
        protected int unsigned pending_ids[$];
        protected bit [LINE_WIDTH-1:0] expected_data[bit [ADDR_WIDTH-1:0]];
        protected bit expect_exact = 1;
        protected int requests = 0;
        protected int responses = 0;
        protected int exact_matches = 0;
        protected int stalled_samples = 0;
        protected int snapshot_matches = 0;
        protected bit [ADDR_WIDTH-1:0] request_address[int unsigned];
        protected bit previous_stall = 0;
        protected logic [BUS_ID_WIDTH-1:0] held_id;
        protected logic [LINE_WIDTH-1:0] held_data;

        `uvm_component_utils(mshr_memory_timing_test)

        function new(string name = "mshr_memory_timing_test", uvm_component parent = null);
            super.new(name, parent);
            if (get_parent() == null) begin
                `fatal("This component's parent can not be null!!")
            end
            sample_export = new("sample_export", this);
        endfunction

        extern virtual function void build_phase(uvm_phase phase);
        extern virtual function void connect_phase(uvm_phase phase);
        extern virtual task run_phase(uvm_phase phase);
        extern virtual function void check_phase(uvm_phase phase);
        extern virtual function void report_phase(uvm_phase phase);
        extern virtual function void final_phase(uvm_phase phase);
        extern task drive_idle();
        extern task run_checks();
        extern task send_request(int unsigned id, int ordinal);
        extern task wait_for_responses(int count);
        extern function void write(mshr_sample sample);
        extern function void check_response(mshr_sample sample);
        extern function void record_request(mshr_sample sample);
        extern function void check_memory_data();
    endclass

    function void mshr_memory_timing_test::build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", vif) ||
            !uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null ||
            !uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clock_cfg) || clock_cfg == null) begin
            `fatal("Timing harness configuration must come from the top module", "MEM_TIMING_CONFIG")
        end
        if (MSHR_ENTRIES < EXACT_REQUESTS) begin
            `fatal("Timing harness requires at least three available read IDs", "MEM_TIMING_CONFIG")
        end
        memory = mshr_memory_store::type_id::create("memory");
        // initialize() 经 mshr_mem_create DPI 创建 RefModel/MEM/SparseMemory.hpp 的 C++ 实例。
        memory.initialize(cfg.mem_page_size);
        uvm_config_db #(virtual mshr_interface)::set(this, "*", "mshr_vif", vif);
        uvm_config_db #(mshr_config)::set(this, "memory_driver", "mshr_config", cfg);
        uvm_config_db #(mshr_memory_store)::set(this, "memory_driver", "memory", memory);
        monitor = mshr_monitor::type_id::create("monitor", this);
        memory_driver = mshr_memory_driver::type_id::create("memory_driver", this);
    endfunction

    function void mshr_memory_timing_test::connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.monitor_port.connect(memory_driver.monitor_export);
        monitor.monitor_port.connect(sample_export);
    endfunction

    task mshr_memory_timing_test::run_phase(uvm_phase phase);
        phase.raise_objection(this);
        drive_idle();
        fork
            run_checks();
            begin
                repeat (1000 + 8 * cfg.mem_read_latency_cycles) @(negedge vif.clk);
                `fatal("Memory timing harness timed out", "MEM_TIMING_TIMEOUT")
            end
        join_any
        disable fork;
        phase.drop_objection(this);
    endtask

    // 初始化自检模拟的其他IO；内存driver独占驱动请求ready和读响应valid/id/data。
    task mshr_memory_timing_test::drive_idle();

        // 上游分配与合并保持空闲，不在内存代理自检中创建MSHR事务。
        vif.alloc_en <= '0;
        vif.alloc_tag <= '0;
        vif.alloc_index <= '0;
        vif.alloc_way <= '0;
        vif.alloc_isWrite <= '0;
        vif.alloc_wData <= '0;
        vif.alloc_wordOff <= '0;
        vif.alloc_respId <= '0;
        vif.alloc_wbSlot <= '0;
        vif.alloc_hasWb <= '0;
        vif.merge_en <= '0;
        vif.merge_entry <= '0;
        vif.merge_isWrite <= '0;
        vif.merge_wData <= '0;
        vif.merge_wordOff <= '0;
        vif.merge_respId <= '0;

        // 设置查询输入及模拟的查询/资源输出，保持已知空态。
        vif.q0_tag <= '0;
        vif.q0_index <= '0;
        vif.q1_tag <= '0;
        vif.q1_index <= '0;
        vif.m0_hit <= '0;
        vif.m0_entry <= '0;
        vif.m0_mergeable <= '0;
        vif.m0_slotFree <= '0;
        vif.m0_freeSlot <= '0;
        vif.m1_hit <= '0;
        vif.m1_entry <= '0;
        vif.m1_mergeable <= '0;
        vif.m1_slotFree <= '0;
        vif.m1_freeSlot <= '0;
        vif.hasFree <= 1;
        vif.freeEntry <= '0;

        // 本自检只模拟请求源和响应ready，另一方向由真实memory driver驱动。
        vif.memReadReq_valid <= '0;
        vif.memReadReq_payload_addr <= '0;
        vif.memReadReq_payload_id <= '0;
        vif.memReadResp_ready <= '0;

        // 未参与本自检的fill、replay与锁输出保持空闲。
        vif.fill_en <= '0;
        vif.fill_index <= '0;
        vif.fill_way <= '0;
        vif.fill_tag <= '0;
        vif.fill_dirty <= '0;
        vif.fill_line <= '0;
        vif.fillReady <= '0;
        vif.replay_valid <= '0;
        vif.replay_ready <= '0;
        vif.replay_payload_rData <= '0;
        vif.replay_payload_id <= '0;
        vif.replay_payload_isWrite <= '0;
        vif.lockMask <= '0;
    endtask

    // 先检查三笔无背压响应恰好晚 L 拍，再阻塞两笔响应，检查队首等待时 valid/id/data 保持。
    // 第二阶段结束后恢复 ready，两笔响应必须按顺序各完成一次，不能因等待而丢失。
    task mshr_memory_timing_test::run_checks();

        // 先用无背压请求检查配置的精确响应拍数。
        wait (vif.rst_n === 1'b1);
        @(negedge vif.clk);
        vif.memReadResp_ready <= 1;
        for (int index = 0; index < EXACT_REQUESTS; index++) begin
            send_request(index, index + 1);
        end
        wait_for_responses(EXACT_REQUESTS);

        // 再保持响应背压，确认待响应记录不被提前移除。
        expect_exact = 0;
        @(negedge vif.clk);
        vif.memReadResp_ready <= 0;
        send_request(0, EXACT_REQUESTS + 1);
        send_request(1, EXACT_REQUESTS + 2);
        repeat (cfg.mem_read_latency_cycles + 3) @(negedge vif.clk);
        if (responses != EXACT_REQUESTS || pending_ids.size() != 2 || memory_driver.is_idle()) begin
            `error("Backpressured requests were removed before their response handshakes", "MEM_TIMING_QUEUE")
        end
        // 关闭新响应开关不能撤回已经呈现并被背压的队首响应。
        cfg.mem_response_enable = 0;
        repeat (2) @(negedge vif.clk);
        cfg.mem_response_enable = 1;
        vif.memReadResp_ready <= 1;
        wait_for_responses(EXACT_REQUESTS + 2);
        repeat (2) @(negedge vif.clk);
    endtask

    // 预置外部C++内存后模拟一笔读请求；握手后改写外部内存，响应仍须返回请求时的旧快照。
    task mshr_memory_timing_test::send_request(int unsigned id, int ordinal);
        bit [ADDR_WIDTH-1:0] addr;
        bit [LINE_WIDTH-1:0] line_data;

        addr = ADDR_WIDTH'(ordinal * BLOCK_SIZE);
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            line_data[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(ordinal * 'h10000 + word_index);
        end
        expected_data[addr] = line_data;
        // write_line()经mshr_mem_write_line DPI预置外部SparseMemory，不访问DUT。
        memory.write_line(addr, line_data);
        @(negedge vif.clk);
        vif.memReadReq_valid <= 1;
        vif.memReadReq_payload_id <= BUS_ID_WIDTH'(id);
        vif.memReadReq_payload_addr <= addr;
        do begin
            @(vif.mon_cb);
        end while (!(vif.mon_cb.memReadReq_valid === 1'b1 && vif.mon_cb.memReadReq_ready === 1'b1));
        @(negedge vif.clk);
        vif.memReadReq_valid <= 0;
        // 请求已经被monitor接受，此后改变外部内存不应改变这笔在途读的返回数据。
        memory.write_line(addr, ~line_data);
    endtask

    // 按时钟沿等待指定数量的响应，等待期间的错误由采样检查和总超时报出。
    task mshr_memory_timing_test::wait_for_responses(int count);
        while (responses < count) begin
            @(negedge vif.clk);
        end
    endtask

    // 从 monitor 的有效采样独立计拍，先检查已有响应再登记新请求，不读取 driver 的内部周期数。
    function void mshr_memory_timing_test::write(mshr_sample sample);
        if (sample.rst_n !== 1'b1) begin
            return;
        end
        sample_cycle++;
        check_response(sample);
        record_request(sample);
    endfunction

    // 依据本自检记录的接收拍判断响应何时应出现，并检查实际握手的延迟和背压时的稳定性。
    // 没有前项阻塞且 ready=1 时，握手必须恰好晚 L 拍；背压期间只要求保持，不强求握手时间。
    function void mshr_memory_timing_test::check_response(mshr_sample sample);
        int unsigned id;
        int unsigned removed_id;
        longint unsigned elapsed_cycles;

        // 先检查前一拍挂起的响应是否保持。
        if (previous_stall && (sample.memReadResp_valid !== 1'b1 || sample.memReadResp_payload_id !== held_id ||
            sample.memReadResp_payload_rData !== held_data)) begin
            `error("Response changed while ready was low", "MEM_TIMING_STABILITY")
        end

        // 按独立记录的请求接受拍计算到期时间，检查早回、晚回和响应归属。
        if (pending_ids.size() == 0) begin
            if (sample.memReadResp_valid !== 1'b0) begin
                `error("Response appeared without an earlier request", "MEM_TIMING_EARLY")
            end
        end else begin
            id = pending_ids[0];
            elapsed_cycles = sample_cycle - accepted_at[id];
            if (elapsed_cycles >= cfg.mem_read_latency_cycles) begin
                if (sample.memReadResp_valid !== 1'b1 || sample.memReadResp_payload_id !== BUS_ID_WIDTH'(id)) begin
                    `error("The due head response was not presented at the expected edge", "MEM_TIMING_DUE")
                end
            end else if (sample.memReadResp_valid !== 1'b0) begin
                `error("Response appeared before the configured number of cycles", "MEM_TIMING_EARLY")
            end
            if (sample.memReadResp_valid === 1'b1 &&
                sample.memReadResp_payload_rData !== expected_data[request_address[id]]) begin
                `error("Read response does not contain the request-time memory snapshot", "MEM_TIMING_SNAPSHOT")
            end

            // 实际握手后再核对精确延迟并移除这笔请求。
            if (sample.memReadResp_valid === 1'b1 && sample.memReadResp_ready === 1'b1) begin
                if (sample.memReadResp_payload_rData === expected_data[request_address[id]]) begin
                    snapshot_matches++;
                end
                if (exact_response[id]) begin
                    if (elapsed_cycles != cfg.mem_read_latency_cycles) begin
                        `error($sformatf("Expected exactly %0d cycles, observed %0d", cfg.mem_read_latency_cycles, elapsed_cycles), "MEM_TIMING_LATENCY")
                    end else begin
                        exact_matches++;
                    end
                end
                removed_id = pending_ids.pop_front();
                accepted_at.delete(id);
                exact_response.delete(id);
                request_address.delete(id);
                responses++;
            end
        end

        // 保存本拍背压与载荷，供下一拍保持检查；挂起响应不能让driver提前报空闲。
        previous_stall = sample.memReadResp_valid === 1'b1 && sample.memReadResp_ready === 1'b0;
        held_id = sample.memReadResp_payload_id;
        held_data = sample.memReadResp_payload_rData;
        if (previous_stall) begin
            stalled_samples++;
            if (memory_driver.is_idle()) begin
                `error("Driver reports idle while a response is still blocked", "MEM_TIMING_QUEUE")
            end
        end
    endfunction

    // 记录实际读请求握手的拍数、地址和ID，独立追溯响应快照及延迟。
    function void mshr_memory_timing_test::record_request(mshr_sample sample);
        int unsigned id;

        if (sample.memReadReq_valid === 1'b1 && sample.memReadReq_ready === 1'b1) begin
            id = sample.memReadReq_payload_id;
            if (accepted_at.exists(id)) begin
                `fatal("Timing stimulus reused an outstanding ID", "MEM_TIMING_ID")
            end
            accepted_at[id] = sample_cycle;
            request_address[id] = sample.memReadReq_payload_addr;
            exact_response[id] = expect_exact;
            pending_ids.push_back(id);
            requests++;
        end
    endfunction

    // 回读外部C++内存，确认每个请求之后的改写确实发生，避免快照测试因存储未变而空通过。
    function void mshr_memory_timing_test::check_memory_data();
        bit [LINE_WIDTH-1:0] actual_data;

        foreach (expected_data[addr]) begin
            // read_line()经mshr_mem_read_line DPI读取RefModel/MEM/SparseMemory.hpp的当前内容。
            memory.read_line(addr, actual_data);
            if (actual_data !== ~expected_data[addr]) begin
                `error($sformatf("Memory data mismatch at 0x%h", addr), "MEM_TIMING_DATA")
            end
        end
    endfunction

    function void mshr_memory_timing_test::check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (requests != EXACT_REQUESTS + 2 || responses != EXACT_REQUESTS + 2 ||
            exact_matches != EXACT_REQUESTS || snapshot_matches != EXACT_REQUESTS + 2 ||
            stalled_samples < 3 || pending_ids.size() != 0 || request_address.num() != 0 ||
            accepted_at.num() != 0 || !memory_driver.is_idle() || expected_data.num() != EXACT_REQUESTS + 2) begin
            `error("Required memory timing scenarios did not complete", "MEM_TIMING_COVERAGE")
        end
        check_memory_data();
    endfunction

    function void mshr_memory_timing_test::report_phase(uvm_phase phase);
        uvm_report_server server;

        super.report_phase(phase);
        server = uvm_report_server::get_server();
        if (server.get_severity_count(UVM_ERROR) == 0 && server.get_severity_count(UVM_FATAL) == 0) begin
            `info($sformatf("period_ns=%0.3f latency_cycles=%0d requests=%0d responses=%0d exact_matches=%0d snapshot_matches=%0d stalled_samples=%0d",
                clock_cfg.clock_period, cfg.mem_read_latency_cycles, requests, responses,
                exact_matches, snapshot_matches, stalled_samples), "MSHR_MEMORY_TIMING_PASS")
        end
    endfunction

    function void mshr_memory_timing_test::final_phase(uvm_phase phase);
        super.final_phase(phase);
        // close()经mshr_mem_destroy DPI释放C++外部内存实例。
        memory.close();
    endfunction
endpackage

module mshr_memory_timing_check;
    timeunit 1ns;
    timeprecision 1ps;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import mshr_pkg::*;
    import mshr_memory_timing_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    mshr_interface vif(clk, rst_n);

    initial begin
        clk_rst_config clock_cfg;
        mshr_config cfg;
        int latency_cycles;
        real period_ns;

        // 时钟配置只在本 TB 顶层创建；命令行只用于同一自检更换时钟周期和响应拍数。
        clock_cfg = clk_rst_config::type_id::create("clock_cfg");
        cfg = mshr_config::type_id::create("cfg");
        if ($value$plusargs("MEM_TIMING_PERIOD_NS=%f", period_ns)) begin
            clock_cfg.clock_period = period_ns;
        end
        if ($value$plusargs("MEM_TIMING_LATENCY_CYCLES=%d", latency_cycles)) begin
            cfg.mem_read_latency_cycles = latency_cycles;
        end
        if (clock_cfg.clock_period <= 0) begin
            $fatal(1, "Timing harness clock period must be positive");
        end
        uvm_config_db #(clk_rst_config)::set(null, "uvm_test_top", "clk_rst_config", clock_cfg);
        uvm_config_db #(mshr_config)::set(null, "uvm_test_top", "mshr_config", cfg);
        uvm_config_db #(virtual mshr_interface)::set(null, "uvm_test_top", "mshr_vif", vif);
        fork
            forever begin
                #(clock_cfg.clock_period / 2);
                clk = ~clk;
            end
            begin
                repeat (clock_cfg.initial_reset_cycles) @(posedge clk);
                @(negedge clk);
                rst_n <= 1;
            end
            run_test("mshr_memory_timing_test");
        join
    end
endmodule
