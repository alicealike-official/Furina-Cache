// wbb_ref_* / wbb_dpi_last_error 为 DPI 函数，声明由 pkg/wbb_dpi.svh 导入 wbb_pkg。
// C++ 入口在 verif_mshr/dpi/wbb_dpi.cpp，调用 RefModel/Cache/WriteBackBuffer.hpp 中的模型。
class wbb_predictor extends uvm_component;
    uvm_analysis_imp #(wbb_sample, wbb_predictor) monitor_export;
    uvm_analysis_port #(wbb_compare_item) compare_port;
    // DPI 返回的 C++ WriteBackBuffer 实例句柄，模型定义见 RefModel/Cache/WriteBackBuffer.hpp。
    protected chandle model_handle;
    // C++ 稀疏内存的 SV 封装句柄，通过 DPI 访问独立的实际/期望内存实例。
    // 存储实现见 RefModel/MEM/SparseMemory.hpp，SV 封装见 model/wbb_memory_store.sv。
    wbb_memory_store memory;
    bit reset_released;

    `uvm_component_utils(wbb_predictor)

    function new(string name = "wbb_predictor",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_export = new("monitor_export", this);
        compare_port = new("compare_port", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern function void write(wbb_sample tr);
    extern function bit is_empty();
    extern virtual function void check_phase(uvm_phase phase);
    extern virtual function void final_phase(uvm_phase phase);

endclass

function void wbb_predictor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(wbb_memory_store)::get(this, "", "memory", memory)) begin
        `fatal("Shared memory store not found")
    end
    // DPI 调用：校验 SV/C++ 配置并创建 C++ WriteBackBuffer，model_handle 保存返回的实例句柄。
    if (!wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, WBB_ENTRIES,
        SLOT_WIDTH, BUS_ID_WIDTH, model_handle)) begin
        `fatal(wbb_dpi_last_error(), "WBB_DPI")
    end
endfunction

function void wbb_predictor::write(wbb_sample tr);
    wbb_compare_item item;
    if ($isunknown(tr.rst_n)) begin
        `fatal("Reset contains X/Z", "TB_PROTOCOL")
    end
    if (!tr.rst_n) begin
        if (reset_released) begin
            `fatal("Mid-run reset cancellation semantics are not supported", "TB_RESET")
        end
        // DPI 调用：对 model_handle 指向的 C++ WBB 执行 reset()，继续保留该实例。
        if (!wbb_ref_reset(model_handle)) begin
            `fatal(wbb_dpi_last_error(), "WBB_DPI")
        end
        return;
    end
    reset_released = 1;
    // Reject X/Z before converting four-state SV inputs into two-state C++ data.
    if ($isunknown({tr.reserve_en, tr.push_en, tr.send_ready, tr.memWriteResp_valid,
        tr.memWriteResp_ready, tr.q0Addr, tr.q1Addr})) begin
        `fatal("Unknown handshake or query input", "TB_PROTOCOL")
    end
    if ((tr.reserve_en && $isunknown(tr.reserve_addr)) ||
        (tr.push_en && $isunknown({tr.push_slot, tr.push_line})) ||
        (tr.memWriteResp_valid && $isunknown(tr.memWriteResp_payload_id))) begin
        `fatal("Unknown valid input payload", "TB_PROTOCOL")
    end
    item = wbb_compare_item::type_id::create("item");
    item.actual_sample = tr;
    // DPI 调用：wbb_ref_step 在 C++ 中设置本拍输入、读取沿前预测，然后执行一次 WriteBackBuffer::tick()。
    // 接口声明见 pkg/wbb_dpi.svh，适配实现见 verif_mshr/dpi/wbb_dpi.cpp。
    if (!wbb_ref_step(model_handle, tr.reserve_en, tr.reserve_addr, tr.push_en,
        tr.push_slot, tr.push_line, tr.send_ready,
        tr.memWriteResp_valid && tr.memWriteResp_ready, tr.memWriteResp_payload_id,
        tr.q0Addr, tr.q1Addr, item.expected_reserve_ok, item.expected_reserve_slot,
        item.expected_full, item.expected_q0_same, item.expected_q1_same,
        item.expected_send_valid, item.expected_send_addr, item.expected_send_data, item.expected_send_id)) begin
        `fatal(wbb_dpi_last_error(), "WBB_DPI")
    end
    if (item.expected_send_valid && tr.send_ready) begin
        // memory.write_expected 是 model/wbb_memory_store.sv 的 SV 方法。
        // 它通过 sparse_mem_write_line DPI，将模型预测数据写入独立的 C++ 期望内存。
        memory.write_expected(item.expected_send_addr, item.expected_send_data);
    end
    compare_port.write(item);
endfunction

function bit wbb_predictor::is_empty();
    int empty;
    // DPI 调用：读取 C++ WBB 的排空状态到 empty；函数返回值表示本次调用是否成功。
    if (!wbb_ref_empty(model_handle, empty)) begin
        `fatal(wbb_dpi_last_error(), "WBB_DPI")
    end
    return empty != 0;
endfunction

function void wbb_predictor::check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!is_empty()) begin
        `error("Reference WBB has pending/reserved/issued slots at end of run", "WBB_DRAIN")
    end
endfunction

function void wbb_predictor::final_phase(uvm_phase phase);
    super.final_phase(phase);
    if (model_handle != null) begin
        // DPI 调用：销毁 C++ WBB 实例，随后清空 SV 保存的句柄。
        if (!wbb_ref_destroy(model_handle)) begin
            `error(wbb_dpi_last_error(), "WBB_DPI")
        end
        model_handle = null;
    end
endfunction
