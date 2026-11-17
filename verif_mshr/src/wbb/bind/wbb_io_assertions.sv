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
            a_reset_outputs: assert (full === 1'b0 && reserveOk === 1'b1 &&
                send_valid === 1'b0 && q0Same === 1'b0 && q1Same === 1'b0)
            else report_failure(0, "RESET", "Reset must asynchronously empty WBB outputs");
        end
    end

    a_reset_known: assert property (@(posedge clk) !$isunknown(rst_n))
        else report_failure(1, "RESET_X", "rst_n contains X/Z");
    a_reset_seen: assert property (@(posedge clk) rst_n |-> seen_reset)
        else report_failure(1, "RESET_INIT", "Assert reset before using the interface");
    a_reset_inputs: assert property (@(posedge clk) !rst_n |->
        (reserve_en === 1'b0 && push_en === 1'b0 && memWriteResp_valid === 1'b0))
        else report_failure(1, "RESET_INPUT", "Sources must be idle while reset is active");

    a_env_controls: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({reserve_en, push_en, send_ready, memWriteResp_valid}))
        else report_failure(1, "CONTROL_X", "Input enables/ready contain X/Z");
    a_dut_controls: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({reserveOk, full, send_valid, memWriteResp_ready, q0Same, q1Same}))
        else report_failure(0, "CONTROL_X", "Output controls contain X/Z");
    a_env_reserve_address: assert property (@(posedge clk) disable iff (!rst_n)
        reserve_en |-> (!$isunknown(reserve_addr) && reserve_addr % BLOCK_SIZE == 0))
        else report_failure(1, "RESERVE_ADDR", "Enabled reserve must carry a block-aligned known address");
    a_env_queries: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({q0Addr, q1Addr}) && q0Addr % BLOCK_SIZE == 0 && q1Addr % BLOCK_SIZE == 0)
        else report_failure(1, "QUERY_ADDR", "Query ports always carry known block addresses");
    a_env_push_payload: assert property (@(posedge clk) disable iff (!rst_n)
        push_en |-> (!$isunknown({push_slot, push_line}) && $unsigned(push_slot) < WBB_ENTRIES))
        else report_failure(1, "PUSH_PAYLOAD", "Push slot/data unknown or out of range");
    a_dut_send_payload: assert property (@(posedge clk) disable iff (!rst_n)
        send_valid |-> (!$isunknown({send_payload_addr, send_payload_wData, send_payload_id}) &&
            send_payload_addr % BLOCK_SIZE == 0 && $unsigned(send_payload_id) < WBB_ENTRIES))
        else report_failure(0, "SEND_PAYLOAD", "Send address/data/ID unknown, misaligned or noncanonical");
    a_env_response_id: assert property (@(posedge clk) disable iff (!rst_n)
        memWriteResp_valid |-> (!$isunknown(memWriteResp_payload_id) &&
            $unsigned(memWriteResp_payload_id) < WBB_ENTRIES))
        else report_failure(1, "RESPONSE_ID", "Response ID unknown or noncanonical");

    a_dut_send_stable: assert property (@(posedge clk) disable iff (!rst_n)
        send_valid && !send_ready |=> send_valid &&
            $stable({send_payload_addr, send_payload_wData, send_payload_id}))
        else report_failure(0, "SEND_STABLE", "Send valid/payload changed before acceptance");
    a_env_response_stable: assert property (@(posedge clk) disable iff (!rst_n)
        memWriteResp_valid && !memWriteResp_ready |=> memWriteResp_valid &&
            $stable(memWriteResp_payload_id))
        else report_failure(1, "RESPONSE_STABLE", "Memory changed response before acceptance");

    a_dut_capacity: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid |-> (full === (&occupied) && reserveOk === !( &occupied)))
        else report_failure(0, "CAPACITY", "full/reserveOk must reflect pre-edge occupied slots");
    a_dut_reserve_slot: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && reserveOk |-> reserve_slot_free)
        else report_failure(0, "RESERVE_SLOT", "reserveSlot must name a currently free slot");
    a_env_unique_address: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && reserve_fire |-> !duplicate_addr)
        else report_failure(1, "DUPLICATE_ADDR", "Upper level must not reserve an already occupied block");
    a_env_push_owner: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && push_en |-> push_has_reservation)
        else report_failure(1, "PUSH_OWNER", "Push requires an earlier reservation, not a same-edge reserve");
    a_dut_send_owner: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && send_valid |-> send_has_data)
        else report_failure(0, "SEND_OWNER", "Send requires previously pushed and not-yet-issued data");
    a_env_response_owner: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && memWriteResp_valid |-> response_is_issued)
        else report_failure(1, "RESPONSE_OWNER", "Response requires a request accepted on an earlier edge");
    a_dut_query0: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && !$isunknown(q0Addr) |-> q0Same === query0_expected)
        else report_failure(0, "QUERY0", "q0Same must cover all occupied slots, including reserved and issued");
    a_dut_query1: assert property (@(posedge clk) disable iff (!rst_n)
        seen_reset && history_valid && !$isunknown(q1Addr) |-> q1Same === query1_expected)
        else report_failure(0, "QUERY1", "q1Same must cover all occupied slots, including reserved and issued");

    generate
        if (STRICT_NEXT_PUSH) begin : g_strict_push
            a_env_push_next: assert property (@(posedge clk) disable iff (!rst_n)
                seen_reset && history_valid && reserve_fire && reserve_slot_free && !duplicate_addr
                |=> push_en && push_slot == $past(reserveSlot))
                else report_failure(1, "PUSH_NEXT", "Successful reserve requires push to that slot on the next edge");
        end
        for (genvar i = 0; i < WBB_ENTRIES; i++) begin : g_slot
            a_dut_send_content: assert property (@(posedge clk) disable iff (!rst_n)
                seen_reset && history_valid && send_valid && send_has_data && $unsigned(send_payload_id) == i
                |-> send_payload_addr === saved_addr[i] && send_payload_wData === saved_data[i])
                else report_failure(0, "SEND_CONTENT", $sformatf("Slot %0d send differs from accepted reserve/push", i));
            if (CHECK_RR_FAIRNESS) begin : g_fairness
                a_dut_rr_bound: assert property (@(posedge clk) disable iff (!rst_n)
                    seen_reset && history_valid && pending[i] && send_fire && send_has_data &&
                    $unsigned(send_payload_id) != i |-> other_sends[i] < WBB_ENTRIES - 1)
                    else report_failure(0, "RR_BOUND", $sformatf("Slot %0d overtaken by too many accepted sends", i));
            end
            c_reserved_query: cover property (@(posedge clk) disable iff (!rst_n)
                history_valid && occupied[i] && !loaded[i] && q0Addr == saved_addr[i] && q0Same);
            c_issued_query: cover property (@(posedge clk) disable iff (!rst_n)
                history_valid && issued[i] && q1Addr == saved_addr[i] && q1Same);
        end
    endgenerate

    c_reserve_push: cover property (@(posedge clk) disable iff (!rst_n)
        reserve_fire ##1 push_en && push_slot == $past(reserveSlot));
    c_full_release: cover property (@(posedge clk) disable iff (!rst_n)
        full && response_fire ##1 !full);
    c_overlap: cover property (@(posedge clk) disable iff (!rst_n)
        reserve_fire && push_en);
    c_send_stall_release: cover property (@(posedge clk) disable iff (!rst_n)
        send_valid && !send_ready ##1 send_valid && send_ready);
    c_send_and_response: cover property (@(posedge clk) disable iff (!rst_n)
        send_fire && response_fire && send_payload_id != memWriteResp_payload_id);
endmodule
