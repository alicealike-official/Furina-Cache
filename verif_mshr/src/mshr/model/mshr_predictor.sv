// mshr_ref_*是C++ DPI函数，声明由pkg/mshr_dpi.svh导入mshr_pkg。
// 入口实现在verif_mshr/dpi/mshr_dpi.cpp，内部调用RefModel/Cache/MSHR.hpp的原有模型。
class mshr_predictor extends uvm_component;
    uvm_analysis_imp #(mshr_sample, mshr_predictor) monitor_export;
    uvm_analysis_port #(mshr_compare_item) compare_port;
    // 这是DPI返回的C++ MSHR实例句柄，不是SV自写的参考模型，也不是DUT层级句柄。
    protected chandle model_handle;
    protected bit reset_released;

    `uvm_component_utils(mshr_predictor)

    function new(string name = "mshr_predictor",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_export = new("monitor_export", this);
        compare_port = new("compare_port", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern function void write(mshr_sample sample);
    extern protected function bit handle_reset(mshr_sample sample);
    extern protected function void validate_sample(mshr_sample sample);
    extern protected function void predict_sample(mshr_sample sample, mshr_compare_item item);
    extern function bit is_empty();
    extern virtual function void check_phase(uvm_phase phase);
    extern virtual function void final_phase(uvm_phase phase);
endclass

function void mshr_predictor::build_phase(uvm_phase phase);
    super.build_phase(phase);

    // DPI核对SV参数与RefModel/Cache/params.hpp，并创建原有C++ MSHR对象。
    if (!mshr_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, MSHR_ENTRIES,
        MSHR_MAX_PENDING, NUM_SETS, NUM_WAYS, TAG_WIDTH, INDEX_WIDTH, WAY_WIDTH,
        WORD_OFF_WIDTH, ENTRY_WIDTH, SLOT_WIDTH, CPU_ID_WIDTH, BUS_ID_WIDTH,
        WBB_ENTRIES, WBB_SLOT_WIDTH, model_handle)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_DPI")
    end
endfunction

// 消费monitor发布的一拍沿前快照，完成复位/输入检查，再把C++预测与原样采样配对发布。
function void mshr_predictor::write(mshr_sample sample);
    mshr_compare_item item;

    if (sample == null) begin
        `fatal("MSHR predictor received a null sample", "MSHR_SAMPLE")
    end
    if (handle_reset(sample)) begin
        return;
    end
    validate_sample(sample);
    item = mshr_compare_item::type_id::create("item");
    item.actual_sample = sample;
    predict_sample(sample, item);
    compare_port.write(item);
endfunction

// 处理低有效复位；空闲重复复位可以清模型，有在途Entry时先报取消语义尚未定义。
// 这里只复位C++ MSHR，后端稀疏内存及其他组件的队列由各自所有者处理。
function bit mshr_predictor::handle_reset(mshr_sample sample);
    if ($isunknown(sample.rst_n)) begin
        `fatal("Reset contains X/Z", "MSHR_RESET")
    end
    if (sample.rst_n) begin
        reset_released = 1;
        return 0;
    end
    if ({sample.alloc_en, sample.merge_en, sample.memReadResp_valid} !== 3'b000) begin
        `fatal("MSHR input sources must be idle while reset is asserted", "MSHR_RESET_INPUT")
    end
    if (reset_released && !is_empty()) begin
        `fatal("Reset cancellation with active MSHR entries is not defined", "MSHR_RESET")
        return 1;
    end
    // mshr_ref_reset经DPI调用MSHR::reset，继续保留已经创建的C++实例句柄。
    if (!mshr_ref_reset(model_handle)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_DPI")
    end
    reset_released = 0;
    return 1;
endfunction

// 在四态SV值转换成C++两态数据前检查控制和有效输入；无效载荷不强求为零或已知。
function void mshr_predictor::validate_sample(mshr_sample sample);
    if ($isunknown({sample.alloc_en, sample.merge_en, sample.memReadReq_ready,
        sample.memReadResp_valid, sample.fillReady, sample.replay_ready,
        sample.q0_tag, sample.q0_index, sample.q1_tag, sample.q1_index})) begin
        `fatal("MSHR handshake or query input contains X/Z", "MSHR_INPUT_X")
    end
    if ($isunknown(sample.memReadResp_ready)) begin
        `fatal("DUT response ready contains X/Z", "MSHR_DUT_CONTROL_X")
    end
    if (sample.alloc_en && sample.merge_en) begin
        `fatal("Simultaneous alloc and merge require an explicit contract and model support", "MSHR_UPSTREAM_PROTOCOL")
    end
    if (sample.alloc_en && ($isunknown({sample.alloc_tag, sample.alloc_index, sample.alloc_way,
        sample.alloc_isWrite, sample.alloc_wordOff, sample.alloc_respId, sample.alloc_hasWb}) ||
        (sample.alloc_isWrite && $isunknown(sample.alloc_wData)) ||
        (sample.alloc_hasWb && $isunknown(sample.alloc_wbSlot)))) begin
        `fatal("Enabled alloc payload contains X/Z", "MSHR_INPUT_X")
    end
    if (sample.merge_en && ($isunknown({sample.merge_entry, sample.merge_isWrite,
        sample.merge_wordOff, sample.merge_respId}) ||
        (sample.merge_isWrite && $isunknown(sample.merge_wData)))) begin
        `fatal("Enabled merge payload contains X/Z", "MSHR_INPUT_X")
    end
    if (sample.memReadResp_valid && $isunknown({sample.memReadResp_payload_id,
        sample.memReadResp_payload_rData})) begin
        `fatal("Valid read response payload contains X/Z", "MSHR_INPUT_X")
    end
endfunction

// 调用mshr_ref_step取得本拍沿前预测，并在C++内部推进恰好一次MSHR::tick。
// 此DPI在一个入口内读取sendReq/fillReq，避免多个checker误把有呈现副作用的方法重复调用。
function void mshr_predictor::predict_sample(mshr_sample sample, mshr_compare_item item);
    if (!mshr_ref_step(model_handle,
        sample.alloc_en, sample.alloc_tag, sample.alloc_index,
        sample.alloc_way, sample.alloc_isWrite, sample.alloc_wData,
        sample.alloc_wordOff, sample.alloc_respId, sample.alloc_hasWb,
        sample.alloc_wbSlot, sample.merge_en, sample.merge_entry,
        sample.merge_isWrite, sample.merge_wData, sample.merge_wordOff,
        sample.merge_respId, sample.q0_tag, sample.q0_index,
        sample.q1_tag, sample.q1_index, sample.memReadReq_ready,
        sample.memReadResp_valid && sample.memReadResp_ready, sample.memReadResp_payload_id, sample.memReadResp_payload_rData,
        sample.fillReady, sample.replay_ready, item.expected_hasFree,
        item.expected_freeEntry, item.expected_m0_hit, item.expected_m0_entry,
        item.expected_m0_mergeable, item.expected_m0_slotFree, item.expected_m0_freeSlot,
        item.expected_m1_hit, item.expected_m1_entry, item.expected_m1_mergeable,
        item.expected_m1_slotFree, item.expected_m1_freeSlot, item.expected_memReadReq_valid,
        item.expected_memReadReq_payload_addr, item.expected_memReadReq_payload_id, item.expected_fill_en,
        item.expected_fill_tag, item.expected_fill_index, item.expected_fill_way,
        item.expected_fill_dirty, item.expected_fill_line, item.expected_replay_valid,
        item.expected_replay_payload_isWrite, item.expected_replay_payload_id, item.expected_replay_payload_rData)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_DPI")
    end
endfunction

// 经DPI查询C++模型的Entry是否排空；不访问DUT内部，也不推进模型时钟。
function bit mshr_predictor::is_empty();
    int empty;

    if (!mshr_ref_empty(model_handle, empty)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_DPI")
    end
    return empty != 0;
endfunction

function void mshr_predictor::check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!is_empty()) begin
        `error("Reference MSHR still has active entries at end of run", "MSHR_DRAIN")
    end
endfunction

function void mshr_predictor::final_phase(uvm_phase phase);
    super.final_phase(phase);
    if (model_handle != null) begin
        // mshr_ref_destroy经DPI销毁RefModel/Cache/MSHR.hpp中的实例，随后清除SV句柄。
        if (!mshr_ref_destroy(model_handle)) begin
            `error(mshr_dpi_last_error(), "MSHR_DPI")
        end
        model_handle = null;
    end
endfunction
