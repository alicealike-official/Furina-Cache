// Reset contract is active-low asynchronous rst_n. DUT reset wiring is not changed here.
// Define WBB_ALLOW_DELAYED_PUSH to opt out of the default next-edge push requirement.
bind tb_top wbb_io_assertions #(
    .ADDR_WIDTH(wbb_params_pkg::ADDR_WIDTH),
    .LINE_WIDTH(wbb_params_pkg::LINE_WIDTH),
    .BLOCK_SIZE(wbb_params_pkg::BLOCK_SIZE),
    .WBB_ENTRIES(wbb_params_pkg::WBB_ENTRIES),
    .SLOT_WIDTH(wbb_params_pkg::SLOT_WIDTH),
    .BUS_ID_WIDTH(wbb_params_pkg::BUS_ID_WIDTH),
`ifdef WBB_ALLOW_DELAYED_PUSH
    .STRICT_NEXT_PUSH(0)
`else
    .STRICT_NEXT_PUSH(1)
`endif
) u_wbb_io_assertions (
    .clk(clk),
    .rst_n(rst_n),
    .reserve_en(wbb_vif.reserve_en),
    .reserve_addr(wbb_vif.reserve_addr),
    .reserveOk(wbb_vif.reserveOk),
    .reserveSlot(wbb_vif.reserveSlot),
    .push_en(wbb_vif.push_en),
    .push_slot(wbb_vif.push_slot),
    .push_line(wbb_vif.push_line),
    .send_valid(wbb_vif.send_valid),
    .send_ready(wbb_vif.send_ready),
    .send_payload_addr(wbb_vif.send_payload_addr),
    .send_payload_wData(wbb_vif.send_payload_wData),
    .send_payload_id(wbb_vif.send_payload_id),
    .memWriteResp_valid(wbb_vif.memWriteResp_valid),
    .memWriteResp_ready(wbb_vif.memWriteResp_ready),
    .memWriteResp_payload_id(wbb_vif.memWriteResp_payload_id),
    .full(wbb_vif.full),
    .q0Addr(wbb_vif.q0Addr),
    .q0Same(wbb_vif.q0Same),
    .q1Addr(wbb_vif.q1Addr),
    .q1Same(wbb_vif.q1Same)
);
