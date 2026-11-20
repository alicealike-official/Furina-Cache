// Checker self-test using explicit IO traces. No WBB RTL or reference model is instantiated.
module wbb_io_assertions_test;
    timeunit 1ns;
    timeprecision 1ps;
`ifdef TEST_DELAYED_PUSH
    localparam bit STRICT = 0;
`else
    localparam bit STRICT = 1;
`endif
    localparam logic [31:0] FIRST_ADDR = 32'h1000;
    localparam logic [31:0] SECOND_ADDR = 32'h2000;
    localparam logic [127:0] FIRST_LINE = 128'h00112233445566778899aabbccddeeff;
    localparam logic [127:0] SECOND_LINE = ~FIRST_LINE;
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

    // 先核对上一场景错误已全部登记，再复位接口历史并记录本场景计数起点。
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

    // 为首地址预留槽0；返回后紧接的下一采样沿必须完成对应push。
    task reserve_first_line();
        reserve_en = 1;
        reserve_addr = FIRST_ADDR;
        q0Addr = FIRST_ADDR;
        tick();
        reserve_en = 0;
        reserveSlot = 1;
        q0Same = 1;
    endtask

    // 装载首行数据，并在push完成后准备该行的首个合法发送。
    task push_first_line();
        push_en = 1;
        push_slot = 0;
        push_line = FIRST_LINE;
        tick();
        push_en = 0;
        send_valid = 1;
        send_payload_addr = FIRST_ADDR;
        send_payload_wData = FIRST_LINE;
        send_payload_id = 0;
    endtask

    // 构造两槽的预留/push及发送/push重叠，再按指定方式返回响应。
    task two_slots(bit overlap_ack = 0);

        // 先预留首行，再构造首行push与第二行预留同拍。
        reserve_first_line();
        reserve_en = 1;
        reserve_addr = SECOND_ADDR;
        push_en = 1;
        push_slot = 0;
        push_line = FIRST_LINE;
        q1Addr = SECOND_ADDR;
        tick();
        reserve_en = 0;
        reserveOk = 0;
        full = 1;
        q1Same = 1;
        push_slot = 1;
        push_line = SECOND_LINE;

        // 下一沿同时接受首行发送和第二行push。
        send_valid = 1;
        send_ready = 1;
        send_payload_addr = FIRST_ADDR;
        send_payload_wData = FIRST_LINE;
        send_payload_id = 0;
        tick();
        push_en = 0;
        send_payload_addr = SECOND_ADDR;
        send_payload_wData = SECOND_LINE;
        send_payload_id = 1;

        // 第二行发送时，可选择同时返回首行响应。
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

        // 全部响应处理后回到空态，检查没有遗留占用。
        idle_values();
        tick();
    endtask

    // 使用槽1再槽0提交两笔流水：第二次reserve与第一次push同拍，尾部push仍在下一拍完成。
    // 同时检查两笔不同数据的发送和响应；2槽配置下reserve和push各连续2拍，成功重叠1次。
    task reverse_slot_pipeline();

        // 首行使用槽1，先记录与最低空槽不同的合法选择。
        reserve_en = 1;
        reserve_addr = FIRST_ADDR;
        reserveSlot = 1;
        q0Addr = FIRST_ADDR;
        tick();

        // 第二行预留槽0，同时向首行的槽1完成push。
        reserve_addr = SECOND_ADDR;
        reserveSlot = 0;
        push_en = 1;
        push_slot = 1;
        push_line = FIRST_LINE;
        q0Same = 1;
        q1Addr = SECOND_ADDR;
        tick();

        reserve_en = 0;

        // 两槽已占满；完成第二行push并发送首行。
        reserveOk = 0;
        full = 1;
        q1Same = 1;
        push_slot = 0;
        push_line = SECOND_LINE;
        send_valid = 1;
        send_ready = 1;
        send_payload_addr = FIRST_ADDR;
        send_payload_wData = FIRST_LINE;
        send_payload_id = 1;
        tick();

        push_en = 0;

        // 发送第二行，同时接受首行响应，检查不同槽交叉。
        send_payload_addr = SECOND_ADDR;
        send_payload_wData = SECOND_LINE;
        send_payload_id = 0;
        memWriteResp_valid = 1;
        memWriteResp_payload_id = 1;
        tick();

        // 最后接受第二行响应，恢复空态。
        send_valid = 0;
        memWriteResp_payload_id = 0;
        full = 0;
        reserveOk = 1;
        reserveSlot = 1;
        q0Same = 0;
        tick();

        idle_values();
        tick();
    endtask

    initial begin
        idle_values();
        rst_n = 0;
        // 合法场景：完成预留、装载、发送和响应，同时检查请求/响应背压保持。
        restart();
        reserve_first_line();
        push_first_line();
        tick();
        tick();
        send_ready = 1;
        tick();
        send_valid = 0;
        send_ready = 0;
        q1Addr = FIRST_ADDR;
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

        // 合法场景：覆盖同拍重叠、满槽及乱序释放。
        restart();
        two_slots();
        expect_result("overlap, full, out-of-order responses and release", 0, 0);

        // 合法场景：不同槽的发送与响应在同一沿接受。
        restart();
        two_slots(1);
        expect_result("send and response for different slots on the same edge", 0, 0);

        // 合法场景：连续预留/push使用不同槽，并保留最后一笔尾push。
        restart();
        reverse_slot_pipeline();
        expect_result("consecutive reserve/push with different slots and tail push", 0, 0);

        // 模式边界：严格模式缺少下一拍push应报错，延迟模式允许后续push。
        restart();
        reserve_first_line();
        tick();
        if (STRICT) begin
            expect_result("missing next-edge push", 1, 0, "WBB_ENV_PUSH_NEXT");
        end else begin
            push_first_line();
            tick();
            expect_result("explicit delayed-push profile", 0, 0);
        end

        // 输入违约：未预留就push，必须报告槽归属错误。
        restart();
        push_en = 1;
        push_line = FIRST_LINE;
        tick();
        expect_result("push without reservation", 1, 0, "WBB_ENV_PUSH_OWNER");

        // 输入违约：不能用本沿新预留为本沿push提供槽。
        restart();
        reserve_en = 1;
        reserve_addr = FIRST_ADDR;
        push_en = 1;
        push_line = FIRST_LINE;
        tick();
        expect_result("same-edge reserve/push forbidden", 1, 0, "WBB_ENV_PUSH_OWNER");

        // 输入违约：push槽号不是之前承诺的槽。
        restart();
        reserve_first_line();
        push_en = 1;
        push_line = FIRST_LINE;
        push_slot = 1;
        tick();
        expect_result("push wrong slot", 1, 0, "WBB_ENV_PUSH_OWNER");

        // 输入违约：对已经占用的地址重复预留。
        restart();
        reserve_first_line();
        push_en = 1;
        push_line = FIRST_LINE;
        reserve_en = 1;
        reserve_addr = FIRST_ADDR;
        tick();
        expect_result("duplicate address reservation", 1, 0, "WBB_ENV_DUPLICATE_ADDR");

        // 输出违约：发送被阻塞时改变整行数据。
        restart();
        reserve_first_line();
        push_first_line();
        tick();
        send_payload_wData = SECOND_LINE;
        tick();
        expect_result("send data changed under backpressure", 0, 1, "WBB_DUT_SEND_STABLE");

        // 输出违约：未握手就撤回已呈现的发送请求。
        restart();
        reserve_first_line();
        push_first_line();
        tick();
        send_valid = 0;
        tick();
        expect_result("send valid withdrawn under backpressure", 0, 1, "WBB_DUT_SEND_STABLE");

        // 输出违约：槽内还没有push数据就产生发送。
        restart();
        send_valid = 1;
        send_payload_addr = FIRST_ADDR;
        send_payload_wData = FIRST_LINE;
        tick();
        expect_result("send without pushed data", 0, 1, "WBB_DUT_SEND_OWNER");

        // 输出违约：同一生命周期已发送槽重复发送。
        restart();
        reserve_first_line();
        push_first_line();
        send_ready = 1;
        tick();
        tick();
        expect_result("same slot sent twice", 0, 1, "WBB_DUT_SEND_OWNER");

        // 输入违约：响应没有对应的先前发送。
        restart();
        memWriteResp_valid = 1;
        tick();
        expect_result("response without earlier send", 1, 0, "WBB_ENV_RESPONSE_OWNER");

        // 输入违约：当前契约不允许首次发送和响应同沿。
        restart();
        reserve_first_line();
        push_first_line();
        send_ready = 1;
        memWriteResp_valid = 1;
        tick();
        expect_result("zero-cycle response forbidden", 1, 0, "WBB_ENV_RESPONSE_OWNER");

        // 输入违约：响应被阻塞时更换ID。
        restart();
        reserve_first_line();
        push_first_line();
        send_ready = 1;
        tick();
        send_valid = 0;
        memWriteResp_valid = 1;
        memWriteResp_ready = 0;
        tick();
        memWriteResp_payload_id = 1;
        tick();
        expect_result("response ID changed under backpressure", 1, 0, "WBB_ENV_RESPONSE_STABLE");

        // 输入违约：完整总线ID超出合法槽范围。
        restart();
        reserve_first_line();
        push_first_line();
        send_ready = 1;
        tick();
        send_valid = 0;
        memWriteResp_valid = 1;
        memWriteResp_payload_id = 4;
        tick();
        expect_result("noncanonical response ID", 1, 0, "WBB_ENV_RESPONSE_ID");

        // 输出违约：空态却报告满槽且不能预留。
        restart();
        full = 1;
        reserveOk = 0;
        tick();
        expect_result("incorrect full/capacity", 0, 1, "WBB_DUT_CAPACITY");

        // 输出违约：空槽选择指向已经占用的位置。
        restart();
        reserve_first_line();
        reserveSlot = 0;
        push_en = 1;
        push_line = FIRST_LINE;
        tick();
        expect_result("reserveSlot names occupied slot", 0, 1, "WBB_DUT_RESERVE_SLOT");

        // 输出违约：旧push同拍，新的成功预留却返回同一个槽。
        restart();
        reserve_first_line();
        reserve_en = 1;
        reserve_addr = SECOND_ADDR;
        reserveSlot = 0;
        push_en = 1;
        push_slot = 0;
        push_line = FIRST_LINE;
        tick();
        expect_result("concurrent reserve returns the legal push slot", 0, 1, "WBB_DUT_OVERLAP_SLOT");

        // 输出违约：仅预留阶段的地址没有被查询命中。
        restart();
        reserve_first_line();
        q0Same = 0;
        push_en = 1;
        push_line = FIRST_LINE;
        tick();
        expect_result("reserved address missing from query", 0, 1, "WBB_DUT_QUERY0");

        // 输出违约：未占用的地址被错误报告命中。
        restart();
        q1Same = 1;
        tick();
        expect_result("false query hit", 0, 1, "WBB_DUT_QUERY1");

        // 输入违约：有效预留地址不是块对齐地址。
        restart();
        reserve_en = 1;
        reserve_addr = FIRST_ADDR + 1;
        tick();
        expect_result("misaligned reserve", 1, 0, "WBB_ENV_RESERVE_ADDR");

        // 输入违约：常开查询口携带未对齐地址。
        restart();
        q0Addr = FIRST_ADDR + 1;
        tick();
        expect_result("misaligned query", 1, 0, "WBB_ENV_QUERY_ADDR");

        // 输出违约：DUT资源反馈含X。
        restart();
        reserveOk = 1'bx;
        tick();
        expect_result("unknown DUT control", 0, 1, "WBB_DUT_CONTROL_X");

        // 输出违约：背压期间新增候选，不得取代原挂起请求。
        restart();
        // A non-lowest free slot is legal: the architecture does not mandate lowest-free allocation.
        reserveSlot = 1;
        reserve_en = 1;
        reserve_addr = FIRST_ADDR;
        tick();
        reserve_en = 0;
        reserveSlot = 0;
        push_en = 1;
        push_slot = 1;
        push_line = FIRST_LINE;
        tick();
        push_en = 0;
        send_valid = 1;
        send_payload_addr = FIRST_ADDR;
        send_payload_id = 1;
        send_payload_wData = FIRST_LINE;
        reserve_en = 1;
        reserve_addr = SECOND_ADDR;
        tick();
        reserve_en = 0;
        reserveOk = 0;
        full = 1;
        push_en = 1;
        push_slot = 0;
        push_line = SECOND_LINE;
        tick();
        push_en = 0;
        send_payload_addr = SECOND_ADDR;
        send_payload_id = 0;
        send_payload_wData = SECOND_LINE;
        tick();
        expect_result("new candidate must not replace a stalled request", 0, 1, "WBB_DUT_SEND_STABLE");

        // 输出违约：持续待发槽被其他成功发送超越规定次数。
        restart();
        reserve_first_line();
        push_en = 1;
        push_line = FIRST_LINE;
        reserve_en = 1;
        reserve_addr = SECOND_ADDR;
        tick();
        reserve_en = 0;
        reserveOk = 0;
        full = 1;
        push_slot = 1;
        push_line = SECOND_LINE;
        tick();
        push_en = 0;
        send_valid = 1;
        send_ready = 1;
        send_payload_id = 1;
        send_payload_addr = SECOND_ADDR;
        send_payload_wData = SECOND_LINE;
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
        reserve_addr = SECOND_ADDR;
        tick();
        reserve_en = 0;
        full = 1;
        reserveOk = 0;
        push_en = 1;
        push_slot = 1;
        push_line = SECOND_LINE;
        tick();
        push_en = 0;
        send_valid = 1;
        tick();
        expect_result("pending slot overtaken beyond RR bound", 0, 1, "WBB_DUT_RR_BOUND");

        // 复位场景：停钟后检查合法异步清空，并注入未清空输出的负例。
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
