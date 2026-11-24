class wbb_idle_payload_test extends wbb_base_test;
    uvm_analysis_imp #(wbb_sample, wbb_idle_payload_test) monitor_export;
    protected wbb_sample previous_sample;
    protected bit [3:0] changed_fields[2];
    protected int occupied_slots;
    protected bit previous_occupied;
    `uvm_component_utils(wbb_idle_payload_test)

    function new(string name = "wbb_idle_payload_test", uvm_component parent = null);
        super.new(name, parent);
        monitor_export = new("monitor_export", this);
    endfunction

    extern virtual function void connect_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern function void write(wbb_sample sample);
endclass

function void wbb_idle_payload_test::connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    env.agent.monitor.monitor_port.connect(monitor_export);
endfunction

// 从真实IO确认空态和pending阶段的四类无效载荷都发生过变化。
function void wbb_idle_payload_test::write(wbb_sample sample);
    int phase_index;
    if (sample.rst_n !== 1'b1) begin
        previous_sample = null;
        occupied_slots = 0;
        previous_occupied = 0;
        return;
    end
    phase_index = occupied_slots != 0 ? 1 : 0;
    if (previous_sample != null && phase_index == int'(previous_occupied) &&
        {sample.reserve_en, sample.push_en, sample.memWriteResp_valid} === 3'b000 &&
        {previous_sample.reserve_en, previous_sample.push_en, previous_sample.memWriteResp_valid} === 3'b000) begin
        changed_fields[phase_index][0] |= sample.reserve_addr != previous_sample.reserve_addr;
        changed_fields[phase_index][1] |= sample.push_slot != previous_sample.push_slot;
        changed_fields[phase_index][2] |= sample.push_line != previous_sample.push_line;
        changed_fields[phase_index][3] |= sample.memWriteResp_payload_id != previous_sample.memWriteResp_payload_id;
    end
    // 占用由实际接受历史决定，查询地址变化不会被误认为槽释放。
    previous_occupied = phase_index != 0;
    if (sample.reserve_en && sample.reserveOk) begin
        occupied_slots++;
    end
    if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
        occupied_slots--;
    end
    previous_sample = sample;
endfunction

// 正常模型/SVA检查每拍状态；最终仍只能有原来的一笔完整写回，数据必须正确。
task wbb_idle_payload_test::run_sequence();
    wbb_idle_payload_sequence seq;
    seq = wbb_idle_payload_sequence::type_id::create("seq");
    run_scenario(seq, 1);
    for (int phase_index = 0; phase_index < 2; phase_index++) begin
        check_count("inactive payload fields changed", int'(changed_fields[phase_index]), 15);
        `info($sformatf("occupied=%0d changed_fields=%b", phase_index, changed_fields[phase_index]), "WBB_IDLE_PAYLOAD_COVERAGE")
    end
endtask
