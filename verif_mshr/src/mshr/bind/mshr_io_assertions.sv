// 基础IO协议断言。Entry/Slot生命周期及锁矩阵由scoreboard的实际IO历史补充检查。
// fill是自定义使能接口，Q-02未确认前不强加反压payload保持。
module mshr_io_assertions(mshr_interface vif);
    timeunit 1ns;
    timeprecision 1ps;
    import uvm_pkg::*;
    import mshr_params_pkg::*;

    // 将断言错误纳入UVM错误统计，正常回归不能只凭simv退出码判PASS。
    function void report_failure(string id, string message);
        uvm_report_error(id, message);
    endfunction

    // 异步低有效复位后一个仿真精度步检查可见空态，避开NBA更新；不代替物理恢复/移除时序检查。
    always @(negedge vif.rst_n or negedge vif.clk) begin
        #1ps;
        if (vif.rst_n === 1'b0) begin
            a_reset_outputs: assert (vif.hasFree === 1'b1 && vif.m0_hit === 1'b0 &&
                vif.m1_hit === 1'b0 && vif.memReadReq_valid === 1'b0 &&
                vif.fill_en === 1'b0 && vif.replay_valid === 1'b0 && vif.lockMask === '0)
                else report_failure("MSHR_DUT_RESET", "Reset must empty visible MSHR state");
        end
    end

    // 【环境】复位信号每个采样沿已知，复位期间各源端不得提交新事务。
    a_reset_known: assert property (@(posedge vif.clk) !$isunknown(vif.rst_n))
        else report_failure("MSHR_ENV_RESET_X", "Reset contains X/Z");
    a_reset_inputs: assert property (@(posedge vif.clk) !vif.rst_n |->
        (vif.alloc_en === 1'b0 && vif.merge_en === 1'b0 && vif.memReadResp_valid === 1'b0))
        else report_failure("MSHR_ENV_RESET_INPUT", "Sources must be idle during reset");

    // 【环境】正常工作时使能和ready已知；当前模型契约要求alloc与merge互斥。
    a_input_controls: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.alloc_en, vif.merge_en, vif.memReadReq_ready, vif.memReadResp_valid,
            vif.fillReady, vif.replay_ready}))
        else report_failure("MSHR_ENV_CONTROL_X", "Input controls contain X/Z");
    a_single_upstream: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !(vif.alloc_en && vif.merge_en))
        else report_failure("MSHR_ENV_UPSTREAM", "Current profile requires alloc/merge mutually exclusive");

    // 【DUT】容量、有效信号、响应ready、查询hit及锁在复位后必须已知。
    a_output_controls: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.hasFree, vif.m0_hit, vif.m1_hit, vif.memReadReq_valid,
            vif.memReadResp_ready, vif.fill_en, vif.replay_valid, vif.lockMask}))
        else report_failure("MSHR_DUT_CONTROL_X", "Output controls contain X/Z");

    // 【环境】查询没有使能，始终要求tag/index为已知且合法的值。
    a_queries_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.q0_tag, vif.q0_index, vif.q1_tag, vif.q1_index}))
        else report_failure("MSHR_ENV_QUERY_X", "Query address contains X/Z");

    // 【环境】alloc没有ready，提交时必须已经有空Entry，且有效字段及索引合法。
    a_alloc_input: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.alloc_en |-> (vif.hasFree &&
            !$isunknown({vif.alloc_tag, vif.alloc_index, vif.alloc_way, vif.alloc_isWrite,
                vif.alloc_wordOff, vif.alloc_respId, vif.alloc_hasWb}) &&
            $unsigned(vif.alloc_index) < NUM_SETS && $unsigned(vif.alloc_way) < NUM_WAYS &&
            $unsigned(vif.alloc_wordOff) < WORDS_PER_BLOCK &&
            (!vif.alloc_isWrite || !$isunknown(vif.alloc_wData)) &&
            (!vif.alloc_hasWb || (!$isunknown(vif.alloc_wbSlot) && $unsigned(vif.alloc_wbSlot) < WBB_ENTRIES))))
        else report_failure("MSHR_ENV_ALLOC_PAYLOAD", "Allocation fields or capacity invalid");

    // 【环境】merge只携带合法Entry、字偏移和CPU信息；所属阶段/空Slot由IO历史检查。
    a_merge_input: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.merge_en |-> (!$isunknown({vif.merge_entry, vif.merge_isWrite, vif.merge_wordOff, vif.merge_respId}) &&
            $unsigned(vif.merge_entry) < MSHR_ENTRIES && $unsigned(vif.merge_wordOff) < WORDS_PER_BLOCK &&
            (!vif.merge_isWrite || !$isunknown(vif.merge_wData))))
        else report_failure("MSHR_ENV_MERGE_PAYLOAD", "Merge fields invalid");

    // 【DUT】有空Entry/命中查询时才约束有效索引；无效字段不强制为0。
    a_free_entry: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.hasFree |-> (!$isunknown(vif.freeEntry) && $unsigned(vif.freeEntry) < MSHR_ENTRIES))
        else report_failure("MSHR_DUT_FREE_ENTRY", "Invalid freeEntry");
    a_query0_result: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.m0_hit |-> (!$isunknown({vif.m0_entry, vif.m0_mergeable, vif.m0_slotFree}) &&
            $unsigned(vif.m0_entry) < MSHR_ENTRIES &&
            (!vif.m0_slotFree || (!$isunknown(vif.m0_freeSlot) && $unsigned(vif.m0_freeSlot) < MSHR_MAX_PENDING))))
        else report_failure("MSHR_DUT_QUERY0", "Invalid query 0 result");
    a_query1_result: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.m1_hit |-> (!$isunknown({vif.m1_entry, vif.m1_mergeable, vif.m1_slotFree}) &&
            $unsigned(vif.m1_entry) < MSHR_ENTRIES &&
            (!vif.m1_slotFree || (!$isunknown(vif.m1_freeSlot) && $unsigned(vif.m1_freeSlot) < MSHR_MAX_PENDING))))
        else report_failure("MSHR_DUT_QUERY1", "Invalid query 1 result");

    // 【DUT】读请求有效时地址块对齐，整个总线ID必须是Entry位次的规范零扩展。
    a_request_payload: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memReadReq_valid |-> (!$isunknown({vif.memReadReq_payload_addr, vif.memReadReq_payload_id}) &&
            vif.memReadReq_payload_addr % BLOCK_SIZE == 0 && $unsigned(vif.memReadReq_payload_id) < MSHR_ENTRIES))
        else report_failure("MSHR_DUT_REQUEST_PAYLOAD", "Read address or full ID invalid");

    // 【DUT】读请求遇到背压，下一拍必须仍有效，且地址/ID保持；包括解除背压的握手拍。
    a_request_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memReadReq_valid && !vif.memReadReq_ready |=>
        vif.memReadReq_valid && $stable({vif.memReadReq_payload_addr, vif.memReadReq_payload_id}))
        else report_failure("MSHR_DUT_REQUEST_STABLE", "Read request changed while stalled");

    // 【环境】返回行和完整ID已知且范围合法；不截取低位后把非法高位当作合法响应。
    a_response_payload: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memReadResp_valid |-> (!$isunknown({vif.memReadResp_payload_id, vif.memReadResp_payload_rData}) &&
            $unsigned(vif.memReadResp_payload_id) < MSHR_ENTRIES))
        else report_failure("MSHR_ENV_RESPONSE_PAYLOAD", "Read response payload invalid");

    // 【环境】内存响应呈现后若未被接受，下拍仍需保持相同ID和整行数据。
    a_response_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memReadResp_valid && !vif.memReadResp_ready |=>
        vif.memReadResp_valid && $stable({vif.memReadResp_payload_id, vif.memReadResp_payload_rData}))
        else report_failure("MSHR_ENV_RESPONSE_STABLE", "Read response changed while stalled");

    // 【DUT】fill有效时目标、dirty和整行必须已知，set/way索引在配置范围内。
    a_fill_payload: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.fill_en |-> (!$isunknown({vif.fill_index, vif.fill_way, vif.fill_tag, vif.fill_dirty, vif.fill_line}) &&
            $unsigned(vif.fill_index) < NUM_SETS && $unsigned(vif.fill_way) < NUM_WAYS))
        else report_failure("MSHR_DUT_FILL_PAYLOAD", "Fill payload invalid");

    // 【DUT】fill_en即valid；被反压后en和全部载荷保持到接受沿，新候选不得抢占。
    a_fill_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.fill_en && !vif.fillReady |=> vif.fill_en &&
        $stable({vif.fill_tag, vif.fill_index, vif.fill_way, vif.fill_dirty, vif.fill_line}))
        else report_failure("MSHR_DUT_FILL_STABLE", "Fill changed while stalled");

    // 【DUT】replay的类型和ID已知；读Slot的数据也必须已知，写Slot的数据不作功能值要求。
    a_replay_payload: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.replay_valid |-> (!$isunknown({vif.replay_payload_isWrite, vif.replay_payload_id}) &&
            (vif.replay_payload_isWrite || !$isunknown(vif.replay_payload_rData))))
        else report_failure("MSHR_DUT_REPLAY_PAYLOAD", "Replay payload invalid");

    // 【DUT】replay被阻塞时，不得换Entry/Slot、撤回valid或改变类型/ID/载荷。
    a_replay_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.replay_valid && !vif.replay_ready |=> vif.replay_valid &&
        $stable({vif.replay_payload_isWrite, vif.replay_payload_id, vif.replay_payload_rData}))
        else report_failure("MSHR_DUT_REPLAY_STABLE", "Replay changed while stalled");

    // cover只说明相应事件确实出现，不替代以上正确性检查或case计数。
    c_allocation: cover property (@(posedge vif.clk) disable iff (!vif.rst_n) vif.alloc_en);
    c_merge: cover property (@(posedge vif.clk) disable iff (!vif.rst_n) vif.merge_en);
    c_fill: cover property (@(posedge vif.clk) disable iff (!vif.rst_n) vif.fill_en && vif.fillReady);
    c_read_replay: cover property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.replay_valid && vif.replay_ready && !vif.replay_payload_isWrite);
    c_write_replay: cover property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.replay_valid && vif.replay_ready && vif.replay_payload_isWrite);
endmodule
