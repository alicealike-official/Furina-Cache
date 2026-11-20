// 单独检查真实 memory driver 的响应拍数，不实例化 WBB DUT。
// 本文件模拟 DUT 的 send 请求和响应 ready，复用 monitor、memory driver 和 C++ 稀疏内存。
package wbb_memory_timing_pkg;
    timeunit 1ns;
    timeprecision 1ps;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import wbb_params_pkg::*;
    import wbb_pkg::*;
    `include "uvm_macros.svh"
    `include "vutils_macros.svh"

    class wbb_memory_timing_test extends uvm_test;
        localparam int EXACT_REQUESTS = 3;
        virtual wbb_interface vif;
        wbb_config cfg;
        clk_rst_config clock_cfg;
        wbb_monitor monitor;
        wbb_memory_driver memory_driver;
        // C++ SparseMemory 的 SV 封装，定义在 src/wbb/model/wbb_memory_store.sv。
        wbb_memory_store memory;
        uvm_analysis_imp #(wbb_sample, wbb_memory_timing_test) sample_export;
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
        protected bit previous_stall = 0;
        protected logic [BUS_ID_WIDTH-1:0] held_id;

        `uvm_component_utils(wbb_memory_timing_test)

        function new(string name = "wbb_memory_timing_test", uvm_component parent = null);
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
        extern function void write(wbb_sample sample);
        extern function void check_response(wbb_sample sample);
        extern function void record_request(wbb_sample sample);
        extern function void check_memory_data();
    endclass

    function void wbb_memory_timing_test::build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif) ||
            !uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg) || cfg == null ||
            !uvm_config_db #(clk_rst_config)::get(this, "", "clk_rst_config", clock_cfg) || clock_cfg == null) begin
            `fatal("Timing harness configuration must come from the top module", "MEM_TIMING_CONFIG")
        end
        if (WBB_ENTRIES < EXACT_REQUESTS) begin
            `fatal("Timing harness requires at least three available write IDs", "MEM_TIMING_CONFIG")
        end
        memory = wbb_memory_store::type_id::create("memory");
        // initialize() 经 sparse_mem_create DPI 创建 C++ SparseMemory 实例；本自检使用实际存储实例。
        memory.initialize(cfg.mem_page_size);
        uvm_config_db #(virtual wbb_interface)::set(this, "*", "wbb_vif", vif);
        uvm_config_db #(wbb_config)::set(this, "memory_driver", "wbb_config", cfg);
        uvm_config_db #(wbb_memory_store)::set(this, "memory_driver", "memory", memory);
        monitor = wbb_monitor::type_id::create("monitor", this);
        memory_driver = wbb_memory_driver::type_id::create("memory_driver", this);
    endfunction

    function void wbb_memory_timing_test::connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.monitor_port.connect(memory_driver.monitor_export);
        monitor.monitor_port.connect(sample_export);
    endfunction

    task wbb_memory_timing_test::run_phase(uvm_phase phase);
        phase.raise_objection(this);
        drive_idle();
        fork
            run_checks();
            begin
                repeat (1000 + 8 * cfg.mem_write_latency_cycles) @(negedge vif.clk);
                `fatal("Memory timing harness timed out", "MEM_TIMING_TIMEOUT")
            end
        join_any
        disable fork;
        phase.drop_objection(this);
    endtask

    // 初始化由本自检模拟的 DUT 输出；memory driver 继续独占驱动 send_ready 和响应 valid/id。
    task wbb_memory_timing_test::drive_idle();
        vif.reserve_en <= 0;
        vif.reserve_addr <= '0;
        vif.reserveOk <= 1;
        vif.reserveSlot <= '0;
        vif.push_en <= 0;
        vif.push_slot <= '0;
        vif.push_line <= '0;
        vif.send_valid <= 0;
        vif.send_payload_addr <= '0;
        vif.send_payload_wData <= '0;
        vif.send_payload_id <= '0;
        vif.memWriteResp_ready <= 0;
        vif.full <= 0;
        vif.q0Addr <= '0;
        vif.q1Addr <= '0;
        vif.q0Same <= 0;
        vif.q1Same <= 0;
    endtask

    // 先检查三笔无背压响应恰好晚 L 拍，再阻塞两笔响应，检查队首等待时 valid/id 保持。
    // 第二阶段结束后恢复 ready，两笔响应必须按顺序各完成一次，不能因等待而丢失。
    task wbb_memory_timing_test::run_checks();

        // 先用无背压请求检查配置的精确响应拍数。
        wait (vif.rst_n === 1'b1);
        @(negedge vif.clk);
        vif.memWriteResp_ready <= 1;
        for (int index = 0; index < EXACT_REQUESTS; index++) begin
            send_request(index, index + 1);
        end
        wait_for_responses(EXACT_REQUESTS);

        // 再保持响应背压，确认待响应记录不被提前移除。
        expect_exact = 0;
        @(negedge vif.clk);
        vif.memWriteResp_ready <= 0;
        send_request(0, EXACT_REQUESTS + 1);
        send_request(1, EXACT_REQUESTS + 2);
        repeat (cfg.mem_write_latency_cycles + 3) @(negedge vif.clk);
        if (responses != EXACT_REQUESTS || pending_ids.size() != 2 || memory_driver.is_idle()) begin
            `error("Backpressured requests were removed before their response handshakes", "MEM_TIMING_QUEUE")
        end
        vif.memWriteResp_ready <= 1;
        wait_for_responses(EXACT_REQUESTS + 2);
        repeat (2) @(negedge vif.clk);
    endtask

    // 模拟一笔 send 请求，在下降沿驱动并保持到实际握手；每笔使用独立地址和可区分的数据。
    task wbb_memory_timing_test::send_request(int unsigned id, int ordinal);
        bit [ADDR_WIDTH-1:0] addr;
        bit [LINE_WIDTH-1:0] line_data;

        addr = ADDR_WIDTH'(ordinal * BLOCK_SIZE);
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            line_data[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(ordinal * 'h10000 + word_index);
        end
        expected_data[addr] = line_data;
        @(negedge vif.clk);
        vif.send_valid <= 1;
        vif.send_payload_id <= BUS_ID_WIDTH'(id);
        vif.send_payload_addr <= addr;
        vif.send_payload_wData <= line_data;
        do begin
            @(vif.mon_cb);
        end while (!(vif.mon_cb.send_valid === 1'b1 && vif.mon_cb.send_ready === 1'b1));
        @(negedge vif.clk);
        vif.send_valid <= 0;
    endtask

    // 按时钟沿等待指定数量的响应，等待期间的错误由采样检查和总超时报出。
    task wbb_memory_timing_test::wait_for_responses(int count);
        while (responses < count) begin
            @(negedge vif.clk);
        end
    endtask

    // 从 monitor 的有效采样独立计拍，先检查已有响应再登记新请求，不读取 driver 的内部周期数。
    function void wbb_memory_timing_test::write(wbb_sample sample);
        if (sample.rst_n !== 1'b1) begin
            return;
        end
        sample_cycle++;
        check_response(sample);
        record_request(sample);
    endfunction

    // 依据本自检记录的接收拍判断响应何时应出现，并检查实际握手的延迟和背压时的稳定性。
    // 没有前项阻塞且 ready=1 时，握手必须恰好晚 L 拍；背压期间只要求保持，不强求握手时间。
    function void wbb_memory_timing_test::check_response(wbb_sample sample);
        int unsigned id;
        int unsigned removed_id;
        longint unsigned elapsed_cycles;

        // 先检查前一拍挂起的响应是否保持。
        if (previous_stall && (sample.memWriteResp_valid !== 1'b1 || sample.memWriteResp_payload_id !== held_id)) begin
            `error("Response changed while ready was low", "MEM_TIMING_STABILITY")
        end

        // 按独立记录的请求接受拍计算到期时间，检查早回、晚回和响应归属。
        if (pending_ids.size() == 0) begin
            if (sample.memWriteResp_valid !== 1'b0) begin
                `error("Response appeared without an earlier request", "MEM_TIMING_EARLY")
            end
        end else begin
            id = pending_ids[0];
            elapsed_cycles = sample_cycle - accepted_at[id];
            if (elapsed_cycles >= cfg.mem_write_latency_cycles) begin
                if (sample.memWriteResp_valid !== 1'b1 || sample.memWriteResp_payload_id !== BUS_ID_WIDTH'(id)) begin
                    `error("The due head response was not presented at the expected edge", "MEM_TIMING_DUE")
                end
            end else if (sample.memWriteResp_valid !== 1'b0) begin
                `error("Response appeared before the configured number of cycles", "MEM_TIMING_EARLY")
            end

            // 实际握手后再核对精确延迟并移除这笔请求。
            if (sample.memWriteResp_valid === 1'b1 && sample.memWriteResp_ready === 1'b1) begin
                if (exact_response[id]) begin
                    if (elapsed_cycles != cfg.mem_write_latency_cycles) begin
                        `error($sformatf("Expected exactly %0d cycles, observed %0d", cfg.mem_write_latency_cycles, elapsed_cycles), "MEM_TIMING_LATENCY")
                    end else begin
                        exact_matches++;
                    end
                end
                removed_id = pending_ids.pop_front();
                accepted_at.delete(id);
                exact_response.delete(id);
                responses++;
            end
        end

        // 保存本拍背压与载荷，供下一拍保持检查；挂起响应不能让driver提前报空闲。
        previous_stall = sample.memWriteResp_valid === 1'b1 && sample.memWriteResp_ready === 1'b0;
        held_id = sample.memWriteResp_payload_id;
        if (previous_stall) begin
            stalled_samples++;
            if (memory_driver.is_idle()) begin
                `error("Driver reports idle while a response is still blocked", "MEM_TIMING_QUEUE")
            end
        end
    endfunction

    // 记录实际 send 握手的采样拍和 ID，检查未完成的 ID 没有被重复使用。
    function void wbb_memory_timing_test::record_request(wbb_sample sample);
        int unsigned id;

        if (sample.send_valid === 1'b1 && sample.send_ready === 1'b1) begin
            id = sample.send_payload_id;
            if (accepted_at.exists(id)) begin
                `fatal("Timing stimulus reused an outstanding ID", "MEM_TIMING_ID")
            end
            accepted_at[id] = sample_cycle;
            exact_response[id] = expect_exact;
            pending_ids.push_back(id);
            requests++;
        end
    endfunction

    // 经已有 SV 封装读取实际 C++ SparseMemory，核对五笔 send 写入的数据都保留下来。
    function void wbb_memory_timing_test::check_memory_data();
        bit [LINE_WIDTH-1:0] actual_data;

        foreach (expected_data[addr]) begin
            // read_actual() 经 sparse_mem_read_line DPI 读取 RefModel/MEM/SparseMemory.hpp 的存储内容。
            memory.read_actual(addr, actual_data);
            if (actual_data !== expected_data[addr]) begin
                `error($sformatf("Memory data mismatch at 0x%h", addr), "MEM_TIMING_DATA")
            end
        end
    endfunction

    function void wbb_memory_timing_test::check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (requests != EXACT_REQUESTS + 2 || responses != EXACT_REQUESTS + 2 ||
            exact_matches != EXACT_REQUESTS || stalled_samples < 3 || pending_ids.size() != 0 ||
            accepted_at.num() != 0 || !memory_driver.is_idle() || expected_data.num() != EXACT_REQUESTS + 2) begin
            `error("Required memory timing scenarios did not complete", "MEM_TIMING_COVERAGE")
        end
        check_memory_data();
    endfunction

    function void wbb_memory_timing_test::report_phase(uvm_phase phase);
        uvm_report_server server;

        super.report_phase(phase);
        server = uvm_report_server::get_server();
        if (server.get_severity_count(UVM_ERROR) == 0 && server.get_severity_count(UVM_FATAL) == 0) begin
            `info($sformatf("period_ns=%0.3f latency_cycles=%0d requests=%0d responses=%0d exact_matches=%0d stalled_samples=%0d",
                clock_cfg.clock_period, cfg.mem_write_latency_cycles, requests, responses,
                exact_matches, stalled_samples), "MEMORY_TIMING_PASS")
        end
    endfunction

    function void wbb_memory_timing_test::final_phase(uvm_phase phase);
        super.final_phase(phase);
        // close() 经 sparse_mem_destroy DPI 释放两份 C++ SparseMemory，避免自检泄漏模型实例。
        memory.close();
    endfunction
endpackage

module wbb_memory_timing_check;
    timeunit 1ns;
    timeprecision 1ps;
    import uvm_pkg::*;
    import clk_rst_pkg::*;
    import wbb_pkg::*;
    import wbb_memory_timing_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    wbb_interface vif(clk, rst_n);

    initial begin
        clk_rst_config clock_cfg;
        wbb_config cfg;
        int latency_cycles;
        real period_ns;

        // 时钟配置只在本 TB 顶层创建；命令行只用于同一自检更换时钟周期和响应拍数。
        clock_cfg = clk_rst_config::type_id::create("clock_cfg");
        cfg = wbb_config::type_id::create("cfg");
        if ($value$plusargs("MEM_TIMING_PERIOD_NS=%f", period_ns)) begin
            clock_cfg.clock_period = period_ns;
        end
        if ($value$plusargs("MEM_TIMING_LATENCY_CYCLES=%d", latency_cycles)) begin
            cfg.mem_write_latency_cycles = latency_cycles;
        end
        if (clock_cfg.clock_period <= 0) begin
            $fatal(1, "Timing harness clock period must be positive");
        end
        uvm_config_db #(clk_rst_config)::set(null, "uvm_test_top", "clk_rst_config", clock_cfg);
        uvm_config_db #(wbb_config)::set(null, "uvm_test_top", "wbb_config", cfg);
        uvm_config_db #(virtual wbb_interface)::set(null, "uvm_test_top", "wbb_vif", vif);
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
            run_test("wbb_memory_timing_test");
        join
    end
endmodule
