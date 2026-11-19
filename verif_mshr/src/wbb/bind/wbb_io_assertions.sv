// WBB IP IO contract checker. Specification: Architecture/WBB_IP架构设计文档.md.
// Only port history is stored; no RTL hierarchy or C++ prediction is used.
`ifndef WBB_SVA_STANDALONE
`include "uvm_macros.svh"
`endif
module wbb_io_assertions #(
    parameter int ADDR_WIDTH = 32,
    parameter int LINE_WIDTH = 512,
    parameter int BLOCK_SIZE = 64,
    parameter int WBB_ENTRIES = 4,
    parameter int SLOT_WIDTH = 2,
    parameter int BUS_ID_WIDTH = 4,
    parameter bit STRICT_NEXT_PUSH = 1,
    parameter bit CHECK_RR_FAIRNESS = 1
) (
    input logic clk,
    input logic rst_n,
    input logic reserve_en,
    input logic [ADDR_WIDTH-1:0] reserve_addr,
    input logic reserveOk,
    input logic [SLOT_WIDTH-1:0] reserveSlot,
    input logic push_en,
    input logic [SLOT_WIDTH-1:0] push_slot,
    input logic [LINE_WIDTH-1:0] push_line,
    input logic send_valid,
    input logic send_ready,
    input logic [ADDR_WIDTH-1:0] send_payload_addr,
    input logic [LINE_WIDTH-1:0] send_payload_wData,
    input logic [BUS_ID_WIDTH-1:0] send_payload_id,
    input logic memWriteResp_valid,
    input logic memWriteResp_ready,
    input logic [BUS_ID_WIDTH-1:0] memWriteResp_payload_id,
    input logic full,
    input logic [ADDR_WIDTH-1:0] q0Addr,
    input logic q0Same,
    input logic [ADDR_WIDTH-1:0] q1Addr,
    input logic q1Same
);
    timeunit 1ns;
    timeprecision 1ps;
`ifndef WBB_SVA_STANDALONE
    import uvm_pkg::*;
`endif

    // IO-derived obligations, not DUT implementation state.
    logic [WBB_ENTRIES-1:0] occupied = '0;
    logic [WBB_ENTRIES-1:0] loaded = '0;
    logic [WBB_ENTRIES-1:0] issued = '0;
    logic [ADDR_WIDTH-1:0] saved_addr[WBB_ENTRIES];
    logic [LINE_WIDTH-1:0] saved_data[WBB_ENTRIES];
    int unsigned other_sends[WBB_ENTRIES];
    bit seen_reset = 0;
    bit history_valid = 0;
    bit reserve_due = 0;
    logic [SLOT_WIDTH-1:0] due_slot;
    int unsigned env_error_count = 0;
    int unsigned dut_error_count = 0;
    int unsigned rule_error_count[string];

    wire reserve_fire = reserve_en && reserveOk;
    wire send_fire = send_valid && send_ready;
    wire response_fire = memWriteResp_valid && memWriteResp_ready;
    wire [WBB_ENTRIES-1:0] pending = loaded & ~issued;
    logic query0_expected, query1_expected, duplicate_addr;
    logic reserve_slot_free, push_has_reservation, send_has_data, response_is_issued;

    // Report the party responsible for a broken contract, including checker-selftest counters.
    function automatic void report_failure(bit environment, string rule, string message);
        string id;
        id = {environment ? "WBB_ENV_" : "WBB_DUT_", rule};
        if (!rule_error_count.exists(id)) begin
            rule_error_count[id] = 0;
        end
        rule_error_count[id]++;
        if (environment) begin
            env_error_count++;
        end else begin
            dut_error_count++;
        end
`ifdef WBB_SVA_STANDALONE
        $error("[%s] %s", id, message);
`else
        `uvm_error(id, message)
`endif
    endfunction

    // Derive expected capacity/query membership solely from previously accepted IO events.
    always_comb begin
        query0_expected = 0;
        query1_expected = 0;
        duplicate_addr = 0;
        for (int i = 0; i < WBB_ENTRIES; i++) begin
            if (occupied[i]) begin
                query0_expected |= (saved_addr[i] == q0Addr);
                query1_expected |= (saved_addr[i] == q1Addr);
                duplicate_addr |= (saved_addr[i] == reserve_addr);
            end
        end
        reserve_slot_free = 0;
        push_has_reservation = 0;
        send_has_data = 0;
        response_is_issued = 0;
        if (!$isunknown(reserveSlot) && $unsigned(reserveSlot) < WBB_ENTRIES) begin
            reserve_slot_free = !occupied[reserveSlot];
        end
        if (!$isunknown(push_slot) && $unsigned(push_slot) < WBB_ENTRIES) begin
            push_has_reservation = occupied[push_slot] && !loaded[push_slot];
        end
        if (!$isunknown(send_payload_id) && $unsigned(send_payload_id) < WBB_ENTRIES) begin
            send_has_data = occupied[send_payload_id] && loaded[send_payload_id] && !issued[send_payload_id];
        end
        if (!$isunknown(memWriteResp_payload_id) && $unsigned(memWriteResp_payload_id) < WBB_ENTRIES) begin
            response_is_issued = occupied[memWriteResp_payload_id] && issued[memWriteResp_payload_id];
        end
    end

    // Capture valid ownership transfers at the clock edge. Stop semantic comparisons after
    // an illegal transition; reset re-synchronizes history. Independent protocol SVAs stay on.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            occupied <= '0;
            loaded <= '0;
            issued <= '0;
            seen_reset <= 1;
            history_valid <= 1;
            reserve_due <= 0;
            due_slot <= '0;
            for (int i = 0; i < WBB_ENTRIES; i++) begin
                saved_addr[i] <= '0;
                saved_data[i] <= '0;
                other_sends[i] <= 0;
            end
        end else if (seen_reset && history_valid) begin
            reserve_due <= reserve_fire;
            due_slot <= reserveSlot;
            if ($isunknown({reserve_en, reserveOk, push_en, send_valid, send_ready,
                memWriteResp_valid, memWriteResp_ready}) ||
                (reserve_fire && (!reserve_slot_free || duplicate_addr || $isunknown(reserve_addr))) ||
                (push_en && (!push_has_reservation || $isunknown(push_line))) ||
                (send_valid && !send_has_data) ||
                (memWriteResp_valid && !response_is_issued) ||
                (STRICT_NEXT_PUSH && reserve_due && !(push_en && push_slot == due_slot))) begin
                history_valid <= 0;
            end else begin
                if (reserve_fire) begin
                    occupied[reserveSlot] <= 1;
                    saved_addr[reserveSlot] <= reserve_addr;
                end
                if (push_en) begin
                    loaded[push_slot] <= 1;
                    saved_data[push_slot] <= push_line;
                end
                if (send_fire) begin
                    issued[send_payload_id] <= 1;
                end
                if (response_fire) begin
                    occupied[memWriteResp_payload_id] <= 0;
                    loaded[memWriteResp_payload_id] <= 0;
                    issued[memWriteResp_payload_id] <= 0;
                end
                for (int i = 0; i < WBB_ENTRIES; i++) begin
                    if (!pending[i] || (send_fire && $unsigned(send_payload_id) == i)) begin
                        other_sends[i] <= 0;
                    end else if (send_fire) begin
                        other_sends[i] <= other_sends[i] + 1;
                    end
                end
            end
        end
    end

    initial begin
        if (ADDR_WIDTH < 1 || BLOCK_SIZE < 1 || (BLOCK_SIZE & (BLOCK_SIZE - 1)) != 0 ||
            LINE_WIDTH != 8 * BLOCK_SIZE || WBB_ENTRIES < 1 ||
            (WBB_ENTRIES & (WBB_ENTRIES - 1)) != 0 ||
            SLOT_WIDTH < 1 || SLOT_WIDTH < $clog2(WBB_ENTRIES) ||
            BUS_ID_WIDTH < SLOT_WIDTH) begin
            $fatal(1, "Invalid WBB IO checker parameters");
        end
    end

    // Asynchronous reset checks observe outputs after one simulation precision step,
    // avoiding preponed/NBA races. This is not a physical recovery/removal timing check.
    always @(negedge rst_n or negedge clk) begin
        #1ps;
        if (rst_n === 1'b0) begin

            // 【DUT】复位有效时，可见输出必须表示空缓冲：full=0、reserveOk=1、send_valid=0、两个查询均不命中。
            // 在复位下降沿或复位期间的时钟下降沿之后 1 ps 检查，避开同一时间槽的状态更新。
            a_reset_outputs: assert (full === 1'b0 && reserveOk === 1'b1 &&
                send_valid === 1'b0 && q0Same === 1'b0 && q1Same === 1'b0)
            else report_failure(0, "RESET", "Reset must asynchronously empty WBB outputs");
        end
    end

    // 以下并发属性在 clk 上升沿采样；带 disable iff (!rst_n) 的属性在复位拉低时取消在途检查。
    // 带 seen_reset/history_valid 条件的属性依赖有效 IO 历史；历史失效后暂停这些语义检查，直到复位重建。
    // cover 记录场景命中次数，场景是否符合全部协议要求由对应 assert 检查。

    // 【环境】每个上升沿检查 rst_n 为确定的 0 或 1；复位有效期间也检查，防止 X/Z 使复位语义不明确。
    a_reset_known: assert property (@(posedge clk) !$isunknown(rst_n))
        else report_failure(1, "RESET_X", "rst_n contains X/Z");

    // 【环境】rst_n 已释放的采样沿，checker 必须已经观察过有效复位，保证历史状态有初始化基线。
    a_reset_seen: assert property (@(posedge clk) rst_n |-> seen_reset)
        else report_failure(1, "RESET_INIT", "Assert reset before using the interface");

    // 【环境】复位有效的采样沿，reserve_en、push_en 和内存响应 valid 必须为 0，禁止源端提交事务。
    a_reset_inputs: assert property (@(posedge clk) !rst_n |->
        (reserve_en === 1'b0 && push_en === 1'b0 && memWriteResp_valid === 1'b0))
        else report_failure(1, "RESET_INPUT", "Sources must be idle while reset is active");

    // 【环境】正常工作时，上游 reserve/push 使能、内存 send_ready 和响应 valid 必须无 X/Z。
    a_env_controls: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({reserve_en, push_en, send_ready, memWriteResp_valid}))
        else report_failure(1, "CONTROL_X", "Input enables/ready contain X/Z");

    // 【DUT】正常工作时，容量、发送 valid、响应 ready 和两个查询结果必须无 X/Z。
    a_dut_controls: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({reserveOk, full, send_valid, memWriteResp_ready, q0Same, q1Same}))
        else report_failure(0, "CONTROL_X", "Output controls contain X/Z");

    // 【上游】reserve_en=1 时，本拍 reserve_addr 必须已知且按 BLOCK_SIZE 对齐，包括预留失败的尝试。
    a_env_reserve_address: assert property (@(posedge clk) disable iff (!rst_n)
        reserve_en |-> (!$isunknown(reserve_addr) && reserve_addr % BLOCK_SIZE == 0))
        else report_failure(1, "RESERVE_ADDR", "Enabled reserve must carry a block-aligned known address");

    // 【上游】两个查询口没有 enable，正常工作期间 q0Addr/q1Addr 每拍都必须已知且块对齐。
    a_env_queries: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({q0Addr, q1Addr}) && q0Addr % BLOCK_SIZE == 0 && q1Addr % BLOCK_SIZE == 0)
        else report_failure(1, "QUERY_ADDR", "Query ports always carry known block addresses");

    // 【上游】push_en=1 时，槽号和整行数据必须已知，且槽号位于 0 到 WBB_ENTRIES-1。
    a_env_push_payload: assert property (@(posedge clk) disable iff (!rst_n)
        push_en |-> (!$isunknown({push_slot, push_line}) && $unsigned(push_slot) < WBB_ENTRIES))
        else report_failure(1, "PUSH_PAYLOAD", "Push slot/data unknown or out of range");

    // 【DUT】send_valid=1 时，地址、整行数据和完整总线 ID 必须已知，地址块对齐且 ID 小于槽数。
    // 即使 send_ready=0，已呈现的载荷也必须合法；完整 ID 范围检查同时约束零扩展高位。
    a_dut_send_payload: assert property (@(posedge clk) disable iff (!rst_n)
        send_valid |-> (!$isunknown({send_payload_addr, send_payload_wData, send_payload_id}) &&
            send_payload_addr % BLOCK_SIZE == 0 && $unsigned(send_payload_id) < WBB_ENTRIES))
        else report_failure(0, "SEND_PAYLOAD", "Send address/data/ID unknown, misaligned or noncanonical");

    // 【内存】响应 valid=1 时，完整响应 ID 必须已知且小于槽数，响应被反压时也要满足。
    a_env_response_id: assert property (@(posedge clk) disable iff (!rst_n)
        memWriteResp_valid |-> (!$isunknown(memWriteResp_payload_id) &&
            $unsigned(memWriteResp_payload_id) < WBB_ENTRIES))
        else report_failure(1, "RESPONSE_ID", "Response ID unknown or noncanonical");

    // 【DUT】本拍 send_valid=1 且 send_ready=0，下一上升沿必须继续保持 valid，并保持地址、数据和 ID。
    // 下一拍即使 ready 已变为 1，握手时仍需交付原请求；连续反压会逐拍重复检查。
    a_dut_send_stable: assert property (@(posedge clk) disable iff (!rst_n)
        send_valid && !send_ready |=> send_valid &&
            $stable({send_payload_addr, send_payload_wData, send_payload_id}))
        else report_failure(0, "SEND_STABLE", "Send valid/payload changed before acceptance");

    // 【内存】本拍响应有效但未被接受，下一上升沿响应 valid 和 ID 必须保持，直到握手完成。
    a_env_response_stable: assert property (@(posedge clk) disable iff (!rst_n)
        memWriteResp_valid && !memWriteResp_ready |=> memWriteResp_valid &&
            $stable(memWriteResp_payload_id))
        else report_failure(1, "RESPONSE_STABLE", "Memory changed response before acceptance");

    // 【DUT】历史有效时，full 必须等于沿前所有槽均占用，reserveOk 必须等于至少还有一个空槽。
    // 占用包含已预留、已装载和已发送未响应的槽，本拍响应释放的资源要到沿后才可见。
    a_dut_capacity: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid |-> (full === (&occupied) && reserveOk === !( &occupied)))
        else report_failure(0, "CAPACITY", "full/reserveOk must reflect pre-edge occupied slots");

    // 【DUT】reserveOk=1 时，reserveSlot 必须指向沿前的空槽；即使本拍 reserve_en=0 也检查候选。
    // 这里仅检查槽号已知、范围合法且未占用，不限定多个空槽之间的选择顺序。
    a_dut_reserve_slot: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && reserveOk |-> reserve_slot_free)
        else report_failure(0, "RESERVE_SLOT", "reserveSlot must name a currently free slot");

    // 【上游】本拍预留成功时，reserve_addr 不得与任何沿前已占用槽同址。
    // 本拍即将收到响应的旧槽仍算占用，因此同地址重新预留需等释放后的下一拍。
    a_env_unique_address: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && reserve_fire |-> !duplicate_addr)
        else report_failure(1, "DUPLICATE_ADDR", "Upper level must not reserve an already occupied block");

    // 【上游】push_en=1 时，目标槽必须已经预留且尚未装载，禁止无主 push、重复 push 或覆盖在途槽。
    // 使用沿前历史判断，所以本拍新 reserve 的槽不能在同一拍被 push。
    a_env_push_owner: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && push_en |-> push_has_reservation)
        else report_failure(1, "PUSH_OWNER", "Push requires an earlier reservation, not a same-edge reserve");

    // 【DUT】呈现 send_valid 时，对应 ID 必须属于此前已装载且尚未发送的占用槽。
    // 禁止未 push 就发送、同拍 push 直通发送，以及同槽已握手后再次发送。
    a_dut_send_owner: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && send_valid |-> send_has_data)
        else report_failure(0, "SEND_OWNER", "Send requires previously pushed and not-yet-issued data");

    // 【内存】呈现响应 valid 时，该 ID 必须对应沿前已发送且尚未释放的槽。
    // 检查在响应握手前就生效，可发现未发先回、重复响应和首次 send 同拍返回响应。
    a_env_response_owner: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && memWriteResp_valid |-> response_is_issued)
        else report_failure(1, "RESPONSE_OWNER", "Response requires a request accepted on an earlier edge");

    // 【DUT】历史有效且 q0Addr 已知时，q0Same 必须准确反映它是否匹配任一沿前占用槽的地址。
    // 查询范围包括 reserved、pending 和 issued；新预留及响应释放的变化在沿后生效。
    a_dut_query0: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && !$isunknown(q0Addr) |-> q0Same === query0_expected)
        else report_failure(0, "QUERY0", "q0Same must cover all occupied slots, including reserved and issued");

    // 【DUT】历史有效且 q1Addr 已知时，q1Same 必须准确反映它是否匹配任一沿前占用槽的地址。
    // 查询口 1 独立检查，可与查询口 0 同址或异址。
    a_dut_query1: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && !$isunknown(q1Addr) |-> q1Same === query1_expected)
        else report_failure(0, "QUERY1", "q1Same must cover all occupied slots, including reserved and issued");

    generate
        if (STRICT_NEXT_PUSH) begin : g_strict_push

            // 【上游】严格模式下，本拍合法预留成功，下一上升沿必须 push，且 push_slot 等于成功沿的 reserveSlot。
            // 使用 $past 锁定上一拍返回的槽号；期间复位会取消本次时序检查，延迟模式不生成此断言。
            a_env_push_next: assert property (@(posedge clk) disable iff (!rst_n)
                seen_reset && history_valid && reserve_fire && reserve_slot_free && !duplicate_addr
                |=> push_en && push_slot == $past(reserveSlot))
                else report_failure(1, "PUSH_NEXT", "Successful reserve requires push to that slot on the next edge");
        end
        for (genvar i = 0; i < WBB_ENTRIES; i++) begin : g_slot

            // 【DUT】槽 i 的发送有效且归属合法时，发送地址必须等于该槽成功 reserve 的地址，数据等于其 push 数据。
            // 有效但受反压时同样比较，发现槽号、地址或整行数据串扰。
            a_dut_send_content: assert property (@(posedge clk) disable iff (!rst_n)
                seen_reset && history_valid && send_valid && send_has_data && $unsigned(send_payload_id) == i
                |-> send_payload_addr === saved_addr[i] && send_payload_wData === saved_data[i])
                else report_failure(0, "SEND_CONTENT", $sformatf("Slot %0d send differs from accepted reserve/push", i));
            if (CHECK_RR_FAIRNESS) begin : g_fairness

                // 【DUT】槽 i 持续待发时，其他槽的成功发送最多允许超越它 WBB_ENTRIES-1 次。
                // 每次其他槽握手前检查此前的超越次数；统计单位是成功握手次数，外部反压等待拍不计入。
                a_dut_rr_bound: assert property (@(posedge clk) disable iff (!rst_n)
                    seen_reset && history_valid && pending[i] && send_fire && send_has_data &&
                    $unsigned(send_payload_id) != i |-> other_sends[i] < WBB_ENTRIES - 1)
                    else report_failure(0, "RR_BOUND", $sformatf("Slot %0d overtaken by too many accepted sends", i));
            end

            // 【覆盖】记录 q0 查询命中槽 i 的 reserved 阶段，即槽已占用但数据尚未 push 的场景。
            c_reserved_query: cover property (@(posedge clk) disable iff (!rst_n)
                history_valid && occupied[i] && !loaded[i] && q0Addr == saved_addr[i] && q0Same);

            // 【覆盖】记录 q1 查询命中槽 i 的 issued 阶段，确认测试观察到了等待写响应期间的地址占用。
            c_issued_query: cover property (@(posedge clk) disable iff (!rst_n)
                history_valid && issued[i] && q1Addr == saved_addr[i] && q1Same);
        end
    endgenerate

    // 【覆盖】记录本拍预留成功、下一拍向上一拍返回的槽号 push 的完整两拍时序。
    c_reserve_push: cover property (@(posedge clk) disable iff (!rst_n)
        reserve_fire ##1 push_en && push_slot == $past(reserveSlot));

    // 【覆盖】记录本拍 WBB 满且接受写响应、下一拍 full 解除的场景。
    c_full_release: cover property (@(posedge clk) disable iff (!rst_n)
        full && response_fire ##1 !full);

    // 【覆盖】记录同一采样沿既有成功 reserve 又有 push 的并发场景，具体槽归属由相应 assert 检查。
    c_overlap: cover property (@(posedge clk) disable iff (!rst_n)
        reserve_fire && push_en);

    // 【覆盖】记录本拍发送被反压、紧接下一拍完成发送握手的场景，载荷保持由 a_dut_send_stable 检查。
    c_send_stall_release: cover property (@(posedge clk) disable iff (!rst_n)
        send_valid && !send_ready ##1 send_valid && send_ready);

    // 【覆盖】记录同一采样沿发送一个槽的请求，同时接受另一个槽的写响应，两个 ID 必须不同。
    c_send_and_response: cover property (@(posedge clk) disable iff (!rst_n)
        send_fire && response_fire && send_payload_id != memWriteResp_payload_id);
endmodule
