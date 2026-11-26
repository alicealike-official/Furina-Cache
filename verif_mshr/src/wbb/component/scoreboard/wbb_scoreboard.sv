class wbb_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(wbb_compare_item, wbb_scoreboard) compare_export;
    // C++ 稀疏内存的 SV 封装句柄，通过 DPI 访问独立的实际/期望内存实例。
    // 存储实现见 RefModel/MEM/SparseMemory.hpp，SV 封装见 model/wbb_memory_store.sv。
    wbb_memory_store memory;
    wbb_sample previous_sample;
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
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        compare_export = new("compare_export", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    int reset_unpushed, reset_unsent, reset_unacked;
    extern function void reset_history();
    extern function void write(wbb_compare_item item);
    extern virtual function void check_phase(uvm_phase phase);
    extern virtual function void report_phase(uvm_phase phase);

endclass

function void wbb_scoreboard::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(wbb_memory_store)::get(this, "", "memory", memory)) begin
        `fatal("Shared memory store not found")
    end
endfunction

// 比较同一拍的实际IO和C++预测，独立检查请求保持，再累计真实握手。
function void wbb_scoreboard::write(wbb_compare_item item);
    wbb_sample sample;

    // 取得同一拍的实际采样和C++预测，先比较容量与地址查询。
    sample = item.actual_sample;
    if (!sample.rst_n) begin
        reset_history();
        return;
    end
    checked_cycles++;
    if (sample.reserveOk !== (item.expected_reserve_ok != 0) || sample.full !== (item.expected_full != 0)) begin
        `error("Capacity outputs differ from C++ WBB model", "WBB_CAPACITY")
    end
    if (item.expected_reserve_ok && sample.reserveSlot !== SLOT_WIDTH'(item.expected_reserve_slot)) begin
        `error("Reserved slot differs from C++ WBB model", "WBB_RESERVE")
    end
    if (sample.q0Same !== (item.expected_q0_same != 0) || sample.q1Same !== (item.expected_q1_same != 0)) begin
        `error("Address queries differ from C++ WBB model", "WBB_QUERY")
    end

    // 比较发送有效性及地址、数据、ID；无效载荷不作功能比较。
    if (sample.send_valid !== (item.expected_send_valid != 0)) begin
        `error("Send valid differs from C++ WBB model", "WBB_SEND")
    end
    if (item.expected_send_valid && (sample.send_payload_addr !== item.expected_send_addr ||
        sample.send_payload_id !== BUS_ID_WIDTH'(item.expected_send_id) ||
        sample.send_payload_wData !== item.expected_send_data)) begin
        `error("Write address/data/ID differs from C++ WBB model", "WBB_SEND")
    end
    if (sample.memWriteResp_ready !== 1'b1) begin
        `error("Current WBB contract requires write-response ready high", "WBB_RESPONSE")
    end
    // Protocol checking does not predict WBB behavior.

    // 独立检查上一拍已挂起请求的保持，不能只依赖模型一致。
    if (previous_sample != null && previous_sample.send_valid && !previous_sample.send_ready) begin
        if (sample.send_valid !== 1'b1 || sample.send_payload_id !== previous_sample.send_payload_id ||
            sample.send_payload_addr !== previous_sample.send_payload_addr ||
            sample.send_payload_wData !== previous_sample.send_payload_wData) begin
            `error("Send payload changed while backpressured", "WBB_STABILITY")
        end
    end

    // 仅按实际接受事件累计四类事务，并记录满槽/背压周期。
    if (sample.reserve_en && sample.reserveOk) begin
        reserve_count++;
    end
    if (sample.push_en) begin
        push_count++;
    end
    if (sample.send_valid && sample.send_ready) begin
        send_count++;
    end
    if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
        response_count++;
    end
    if (sample.full) begin
        full_cycles++;
    end
    if (sample.send_valid && !sample.send_ready) begin
        stalled_cycles++;
    end

    // 保留本拍采样，供下一拍的背压保持检查使用。
    previous_sample = sample;
endfunction

function void wbb_scoreboard::check_phase(uvm_phase phase);
    super.check_phase(phase);
    // 调用 model/wbb_memory_store.sv 的 SV 封装，经 sparse_mem_read_line DPI
    // 回读两份 C++ SparseMemory 的受测地址，并比较实际值与期望值。
    memory.compare_contents();
    if (reserve_count != push_count + reset_unpushed || push_count != send_count + reset_unsent || send_count != response_count + reset_unacked) begin
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

// 清除跨复位的保持义务，累计各阶段被取消的实际数量；既有错误计数不清零。
function void wbb_scoreboard::reset_history();
    reset_unpushed = reserve_count - push_count;
    reset_unsent = push_count - send_count;
    reset_unacked = send_count - response_count;
    previous_sample = null;
endfunction
