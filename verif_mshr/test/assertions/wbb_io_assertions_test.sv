// Checker self-test using explicit IO traces. No WBB RTL or reference model is instantiated.
module wbb_io_assertions_test;
    timeunit 1ns;
    timeprecision 1ps;
`ifdef TEST_DELAYED_PUSH
    localparam bit STRICT = 0;
`else
    localparam bit STRICT = 1;
`endif
    localparam logic [31:0] A = 32'h1000;
    localparam logic [31:0] B = 32'h2000;
    localparam logic [127:0] D = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] E = ~D;
    real clock_period_ns = 10.0;
    logic reference_clk = 0;
    logic clk = 0;
    logic rst_n = 1;
    bit clock_enable = 1;
    int env_before, dut_before;
    int scenarios = 0;
    int accounted_env = 0;
    int accounted_dut = 0;
    int unsigned rules_before[string];
    logic reserve_en;
    logic [31:0] reserve_addr;
    logic reserveOk;
    logic reserveSlot;
    logic push_en;
    logic push_slot;
    logic [127:0] push_line;
    logic send_valid;
    logic send_ready;
    logic [31:0] send_payload_addr;
    logic [127:0] send_payload_wData;
    logic [2:0] send_payload_id;
    logic memWriteResp_valid;
    logic memWriteResp_ready;
    logic [2:0] memWriteResp_payload_id;
    logic full;
    logic [31:0] q0Addr;
    logic q0Same;
    logic [31:0] q1Addr;
    logic q1Same;

    initial begin
        // 本自测的时钟由模块顶层配置；先读取参数，再开始生成第一个半周期。
        void'($value$plusargs("CLOCK_PERIOD_NS=%f", clock_period_ns));
        if (clock_period_ns <= 0) begin
            $fatal(1, "CLOCK_PERIOD_NS must be positive");
        end
        $display("CHECKER_CLOCK_CONFIG period_ns=%0.3f", clock_period_ns);
        forever begin
            #(clock_period_ns / 2);
            // reference_clk 一直运行，供停钟复位场景和总超时计数使用。
            reference_clk = ~reference_clk;
            if (clock_enable) begin
                clk = reference_clk;
            end
        end
    end

    wbb_io_assertions #(
        .ADDR_WIDTH(32), .LINE_WIDTH(128), .BLOCK_SIZE(16),
        .WBB_ENTRIES(2), .SLOT_WIDTH(1), .BUS_ID_WIDTH(3),
        .STRICT_NEXT_PUSH(STRICT)
    ) checks (
        .clk(clk), .rst_n(rst_n),
        .reserve_en(reserve_en),
        .reserve_addr(reserve_addr),
        .reserveOk(reserveOk),
        .reserveSlot(reserveSlot),
        .push_en(push_en),
        .push_slot(push_slot),
        .push_line(push_line),
        .send_valid(send_valid),
        .send_ready(send_ready),
        .send_payload_addr(send_payload_addr),
        .send_payload_wData(send_payload_wData),
        .send_payload_id(send_payload_id),
        .memWriteResp_valid(memWriteResp_valid),
        .memWriteResp_ready(memWriteResp_ready),
        .memWriteResp_payload_id(memWriteResp_payload_id),
        .full(full),
        .q0Addr(q0Addr),
        .q0Same(q0Same),
        .q1Addr(q1Addr),
        .q1Same(q1Same)
    );

    // Drive a fully empty, inactive interface; callers select events for each trace edge.
    task idle_values();
        reserve_en = '0;
        reserve_addr = '0;
        reserveOk = '0;
        reserveSlot = '0;
        push_en = '0;
        push_slot = '0;
        push_line = '0;
        send_valid = '0;
        send_ready = '0;
        send_payload_addr = '0;
        send_payload_wData = '0;
        send_payload_id = '0;
        memWriteResp_valid = '0;
        memWriteResp_ready = '0;
        memWriteResp_payload_id = '0;
        full = '0;
        q0Addr = '0;
        q0Same = '0;
        q1Addr = '0;
        q1Same = '0;
        reserveOk = 1;
        memWriteResp_ready = 1;
    endtask

    // 等待一个上升沿完成检查，再在紧接着的下降沿返回，供下一拍修改接口输入。
    task tick();
        @(posedge clk);
        @(negedge clk);
    endtask

    // Reset the history and start each scenario from an explicitly empty IO trace.
    task restart();
        if (checks.env_error_count != accounted_env || checks.dut_error_count != accounted_dut) begin
            $fatal(1, "Unexpected assertion outside a checked scenario");
        end
        rst_n = 0;
        idle_values();
        tick();
        rst_n = 1;
        env_before = checks.env_error_count;
        dut_before = checks.dut_error_count;
        rules_before = checks.rule_error_count;
    endtask

    // 检查本场景应报告哪一方的错误，并确认没有额外报错；指定规则时还要确认该规则被触发。
    task expect_result(string name, bit expect_env, bit expect_dut, string expected_rule = "");
        // 等待断言的报错计数更新完成。这里的2 ps是仿真调度等待，不表示协议延迟。
        #2ps;
        if ((checks.env_error_count > env_before) != expect_env ||
            (checks.dut_error_count > dut_before) != expect_dut) begin
            $fatal(1, "%s: expected env/dut=%0d/%0d, observed=%0d/%0d", name,
                expect_env, expect_dut, checks.env_error_count - env_before,
                checks.dut_error_count - dut_before);
        end
        if (expected_rule != "") begin
            if (!checks.rule_error_count.exists(expected_rule)) begin
                $fatal(1, "%s: required assertion %s did not fire", name, expected_rule);
            end
            if (rules_before.exists(expected_rule) &&
                checks.rule_error_count[expected_rule] <= rules_before[expected_rule]) begin
                $fatal(1, "%s: required assertion %s did not fire in this scenario", name, expected_rule);
            end
        end
        accounted_env = checks.env_error_count;
        accounted_dut = checks.dut_error_count;
        scenarios++;
        $display("CHECKER_SCENARIO_PASS %s env=%0d dut=%0d", name,
            checks.env_error_count - env_before, checks.dut_error_count - dut_before);
    endtask

    // Reserve A in slot 0; after returning, the next edge is the mandatory push edge.
    task reserve_a();
        reserve_en = 1;
        reserve_addr = A;
        q0Addr = A;
        tick();
        reserve_en = 0;
        reserveSlot = 1;
        q0Same = 1;
    endtask

    // Complete the previous reservation and prepare the first legal send of its payload.
    task push_a();
        push_en = 1;
        push_slot = 0;
        push_line = D;
        tick();
        push_en = 0;
        send_valid = 1;
        send_payload_addr = A;
        send_payload_wData = D;
        send_payload_id = 0;
    endtask

    // Exercise two slots with concurrent reserve/push and send/push, then out-of-order acks.
    task two_slots(bit overlap_ack = 0);
        reserve_a();
        reserve_en = 1;
        reserve_addr = B;
        push_en = 1;
        push_slot = 0;
        push_line = D;
        q1Addr = B;
        tick();
        reserve_en = 0;
        reserveOk = 0;
        full = 1;
        q1Same = 1;
        push_slot = 1;
        push_line = E;
        send_valid = 1;
        send_ready = 1;
        send_payload_addr = A;
        send_payload_wData = D;
        send_payload_id = 0;
        tick();
        push_en = 0;
        send_payload_addr = B;
        send_payload_wData = E;
        send_payload_id = 1;
        if (overlap_ack) begin
            memWriteResp_valid = 1;
            memWriteResp_payload_id = 0;
        end
        tick();
        send_valid = 0;
        memWriteResp_valid = 1;
        memWriteResp_payload_id = 1;
        if (overlap_ack) begin
            full = 0;
            reserveOk = 1;
            reserveSlot = 0;
            q0Same = 0;
            tick();
        end else begin
            // Full at this edge despite the simultaneous release: reserve fails.
            reserve_en = 1;
            reserve_addr = 32'h3000;
            tick();
            reserve_en = 0;
            full = 0;
            reserveOk = 1;
            reserveSlot = 1;
            q1Same = 0;
            memWriteResp_payload_id = 0;
            tick();
        end
        idle_values();
        tick();
    endtask

    initial begin
        idle_values();
        rst_n = 0;
        restart();
        reserve_a();
        push_a();
        tick();
        tick();
        send_ready = 1;
        tick();
        send_valid = 0;
        send_ready = 0;
        q1Addr = A;
        q1Same = 1;
        memWriteResp_valid = 1;
        memWriteResp_payload_id = 0;
        memWriteResp_ready = 0;
        tick();
        memWriteResp_ready = 1;
        tick();
        idle_values();
        tick();
        expect_result("legal lifecycle and request/response backpressure", 0, 0);

        restart();
        two_slots();
        expect_result("overlap, full, out-of-order responses and release", 0, 0);

        restart();
        two_slots(1);
        expect_result("send and response for different slots on the same edge", 0, 0);

        restart();
        reserve_a();
        tick();
        if (STRICT) begin
            expect_result("missing next-edge push", 1, 0, "WBB_ENV_PUSH_NEXT");
        end else begin
            push_a();
            tick();
            expect_result("explicit delayed-push profile", 0, 0);
        end

        restart();
        push_en = 1;
        push_line = D;
        tick();
        expect_result("push without reservation", 1, 0, "WBB_ENV_PUSH_OWNER");

        restart();
        reserve_en = 1;
        reserve_addr = A;
        push_en = 1;
        push_line = D;
        tick();
        expect_result("same-edge reserve/push forbidden", 1, 0, "WBB_ENV_PUSH_OWNER");

        restart();
        reserve_a();
        push_en = 1;
        push_line = D;
        push_slot = 1;
        tick();
        expect_result("push wrong slot", 1, 0, "WBB_ENV_PUSH_OWNER");

        restart();
        reserve_a();
        push_en = 1;
        push_line = D;
        reserve_en = 1;
        reserve_addr = A;
        tick();
        expect_result("duplicate address reservation", 1, 0, "WBB_ENV_DUPLICATE_ADDR");

        restart();
        reserve_a();
        push_a();
        tick();
        send_payload_wData = E;
        tick();
        expect_result("send data changed under backpressure", 0, 1, "WBB_DUT_SEND_STABLE");

        restart();
        reserve_a();
        push_a();
        tick();
        send_valid = 0;
        tick();
        expect_result("send valid withdrawn under backpressure", 0, 1, "WBB_DUT_SEND_STABLE");

        restart();
        send_valid = 1;
        send_payload_addr = A;
        send_payload_wData = D;
        tick();
        expect_result("send without pushed data", 0, 1, "WBB_DUT_SEND_OWNER");

        restart();
        reserve_a();
        push_a();
        send_ready = 1;
        tick();
        tick();
        expect_result("same slot sent twice", 0, 1, "WBB_DUT_SEND_OWNER");

        restart();
        memWriteResp_valid = 1;
        tick();
        expect_result("response without earlier send", 1, 0, "WBB_ENV_RESPONSE_OWNER");

        restart();
        reserve_a();
        push_a();
        send_ready = 1;
        memWriteResp_valid = 1;
        tick();
        expect_result("zero-cycle response forbidden", 1, 0, "WBB_ENV_RESPONSE_OWNER");

        restart();
        reserve_a();
        push_a();
        send_ready = 1;
        tick();
        send_valid = 0;
        memWriteResp_valid = 1;
        memWriteResp_ready = 0;
        tick();
        memWriteResp_payload_id = 1;
        tick();
        expect_result("response ID changed under backpressure", 1, 0, "WBB_ENV_RESPONSE_STABLE");

        restart();
        reserve_a();
        push_a();
        send_ready = 1;
        tick();
        send_valid = 0;
        memWriteResp_valid = 1;
        memWriteResp_payload_id = 4;
        tick();
        expect_result("noncanonical response ID", 1, 0, "WBB_ENV_RESPONSE_ID");

        restart();
        full = 1;
        reserveOk = 0;
        tick();
        expect_result("incorrect full/capacity", 0, 1, "WBB_DUT_CAPACITY");

        restart();
        reserve_a();
        reserveSlot = 0;
        push_en = 1;
        push_line = D;
        tick();
        expect_result("reserveSlot names occupied slot", 0, 1, "WBB_DUT_RESERVE_SLOT");

        restart();
        reserve_a();
        q0Same = 0;
        push_en = 1;
        push_line = D;
        tick();
        expect_result("reserved address missing from query", 0, 1, "WBB_DUT_QUERY0");

        restart();
        q1Same = 1;
        tick();
        expect_result("false query hit", 0, 1, "WBB_DUT_QUERY1");

        restart();
        reserve_en = 1;
        reserve_addr = A + 1;
        tick();
        expect_result("misaligned reserve", 1, 0, "WBB_ENV_RESERVE_ADDR");

        restart();
        q0Addr = A + 1;
        tick();
        expect_result("misaligned query", 1, 0, "WBB_ENV_QUERY_ADDR");

        restart();
        reserveOk = 1'bx;
        tick();
        expect_result("unknown DUT control", 0, 1, "WBB_DUT_CONTROL_X");

        restart();
        // A non-lowest free slot is legal: the architecture does not mandate lowest-free allocation.
        reserveSlot = 1;
        reserve_en = 1;
        reserve_addr = A;
        tick();
        reserve_en = 0;
        reserveSlot = 0;
        push_en = 1;
        push_slot = 1;
        push_line = D;
        tick();
        push_en = 0;
        send_valid = 1;
        send_payload_addr = A;
        send_payload_id = 1;
        send_payload_wData = D;
        reserve_en = 1;
        reserve_addr = B;
        tick();
        reserve_en = 0;
        reserveOk = 0;
        full = 1;
        push_en = 1;
        push_slot = 0;
        push_line = E;
        tick();
        push_en = 0;
        send_payload_addr = B;
        send_payload_id = 0;
        send_payload_wData = E;
        tick();
        expect_result("new candidate must not replace a stalled request", 0, 1, "WBB_DUT_SEND_STABLE");

        restart();
        reserve_a();
        push_en = 1;
        push_line = D;
        reserve_en = 1;
        reserve_addr = B;
        tick();
        reserve_en = 0;
        reserveOk = 0;
        full = 1;
        push_slot = 1;
        push_line = E;
        tick();
        push_en = 0;
        send_valid = 1;
        send_ready = 1;
        send_payload_id = 1;
        send_payload_addr = B;
        send_payload_wData = E;
        tick();
        send_valid = 0;
        memWriteResp_valid = 1;
        memWriteResp_payload_id = 1;
        tick();
        memWriteResp_valid = 0;
        full = 0;
        reserveOk = 1;
        reserveSlot = 1;
        reserve_en = 1;
        reserve_addr = B;
        tick();
        reserve_en = 0;
        full = 1;
        reserveOk = 0;
        push_en = 1;
        push_slot = 1;
        push_line = E;
        tick();
        push_en = 0;
        send_valid = 1;
        tick();
        expect_result("pending slot overtaken beyond RR bound", 0, 1, "WBB_DUT_RR_BOUND");

        restart();
        clock_enable = 0;
        rst_n = 0;
        idle_values();
        // 被检查的 clk 已停止，用持续运行的参考时钟安排两次异步复位及结果检查。
        @(posedge reference_clk);
        expect_result("asynchronous reset with stopped clock", 0, 0);
        rst_n = 1;
        @(posedge reference_clk);
        rst_n = 0;
        send_valid = 1;
        @(posedge reference_clk);
        expect_result("reset output violation with stopped clock", 0, 1, "WBB_DUT_RESET");

        $display("WBB_SVA_SELFTEST_PASS strict=%0d scenarios=%0d (intentional negative errors expected)", STRICT, scenarios);
        $finish;
    end

    initial begin
        // 按参考时钟的上升沿计数，即使被检查的 clk 停止，超时检查也仍然有效。
        repeat (10000) @(posedge reference_clk);
        $fatal(1, "Checker selftest timeout");
    end
endmodule
