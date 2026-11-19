class wbb_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(wbb_compare_item, wbb_scoreboard) compare_export;
    // C++ 稀疏内存的 SV 封装句柄，通过 DPI 访问独立的实际/期望内存实例。
    // 存储实现见 RefModel/MEM/SparseMemory.hpp，SV 封装见 model/wbb_memory_store.sv。
    wbb_memory_store memory;
    wbb_sample previous;
    int checked_cycles;
    int reserve_count;
    int push_count;
    int send_count;
    int response_count;
    int full_cycles;
    int stalled_cycles;

    `uvm_component_utils(wbb_scoreboard)

    function new(string name = "wbb_scoreboard",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        compare_export = new("compare_export", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern function void write(wbb_compare_item item);
    extern virtual function void check_phase(uvm_phase phase);
    extern virtual function void report_phase(uvm_phase phase);

endclass


function void wbb_scoreboard::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(wbb_memory_store)::get(this, "", "memory", memory)) begin
        `fatal("Shared memory store not found")
    end
endfunction

function void wbb_scoreboard::write(wbb_compare_item item);
    wbb_sample tr;
    tr = item.actual_sample;
    checked_cycles++;
    if (tr.reserveOk !== (item.expected_reserve_ok != 0) || tr.full !== (item.expected_full != 0)) begin
        `error("Capacity outputs differ from C++ WBB model", "WBB_CAPACITY")
    end
    if (item.expected_reserve_ok && tr.reserveSlot !== SLOT_WIDTH'(item.expected_reserve_slot)) begin
        `error("Reserved slot differs from C++ WBB model", "WBB_RESERVE")
    end
    if (tr.q0Same !== (item.expected_q0_same != 0) || tr.q1Same !== (item.expected_q1_same != 0)) begin
        `error("Address queries differ from C++ WBB model", "WBB_QUERY")
    end
    if (tr.send_valid !== (item.expected_send_valid != 0)) begin
        `error("Send valid differs from C++ WBB model", "WBB_SEND")
    end
    if (item.expected_send_valid && (tr.send_payload_addr !== item.expected_send_addr ||
        tr.send_payload_id !== BUS_ID_WIDTH'(item.expected_send_id) ||
        tr.send_payload_wData !== item.expected_send_data)) begin
        `error("Write address/data/ID differs from C++ WBB model", "WBB_SEND")
    end
    if (tr.memWriteResp_ready !== 1'b1) begin
        `error("Current WBB contract requires write-response ready high", "WBB_RESPONSE")
    end
    // Protocol checking does not predict WBB behavior.
    if (previous != null && previous.send_valid && !previous.send_ready) begin
        if (tr.send_valid !== 1'b1 || tr.send_payload_id !== previous.send_payload_id ||
            tr.send_payload_addr !== previous.send_payload_addr ||
            tr.send_payload_wData !== previous.send_payload_wData) begin
            `error("Send payload changed while backpressured", "WBB_STABILITY")
        end
    end
    if (tr.reserve_en && tr.reserveOk) begin
        reserve_count++;
    end
    if (tr.push_en) begin
        push_count++;
    end
    if (tr.send_valid && tr.send_ready) begin
        send_count++;
    end
    if (tr.memWriteResp_valid && tr.memWriteResp_ready) begin
        response_count++;
    end
    if (tr.full) begin
        full_cycles++;
    end
    if (tr.send_valid && !tr.send_ready) begin
        stalled_cycles++;
    end
    previous = tr;
endfunction

function void wbb_scoreboard::check_phase(uvm_phase phase);
    super.check_phase(phase);
    // 调用 model/wbb_memory_store.sv 的 SV 封装，经 sparse_mem_read_line DPI
    // 回读两份 C++ SparseMemory 的受测地址，并比较实际值与期望值。
    memory.compare_contents();
    if (reserve_count != push_count || push_count != send_count || send_count != response_count) begin
        `error("WBB transaction counts do not balance at end of run", "WBB_DRAIN")
    end
    if (checked_cycles == 0) begin
        `error("No post-reset cycles observed during framework startup", "WBB_EMPTY_TEST")
    end
endfunction

function void wbb_scoreboard::report_phase(uvm_phase phase);
    super.report_phase(phase);
    `info($sformatf("cycles=%0d reserve=%0d push=%0d send=%0d response=%0d full_cycles=%0d stalled_cycles=%0d",
        checked_cycles, reserve_count, push_count, send_count, response_count, full_cycles, stalled_cycles))
endfunction
