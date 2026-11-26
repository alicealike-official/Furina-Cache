class mshr_driver extends uvm_driver #(mshr_transaction);
    virtual mshr_interface vif;
    mshr_config cfg;

    `uvm_component_utils(mshr_driver)

    function new(string name = "mshr_driver",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task drive_idle();
    extern task drive_invalid_payload(mshr_transaction item);
    extern task drive_queries(mshr_transaction item);
    extern function void check_transaction(mshr_transaction item);
    extern task drive_transaction(mshr_transaction item);
    extern task drive_reset_release_alloc(mshr_transaction item);
    extern task prepare_request_query(mshr_transaction item);
    extern task wait_for_resources(mshr_transaction item);
    extern function bit request_ready(mshr_transaction item);
    extern task drive_request(mshr_transaction item);
    extern function void check_submission(mshr_transaction item);
    extern task drive_nonrequest(mshr_transaction item);
endclass

function void mshr_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", vif) || vif == null) begin
        `fatal("mshr_interface not found", "MSHR_CONFIG")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null) begin
        `fatal("Parent agent must provide mshr_config", "MSHR_CONFIG")
    end
    // 【防御性检查】等待预算必须为正，避免环境配置导致无效等待或立即超时。
    if (cfg.request_timeout_cycles == 0) begin
        `fatal("request_timeout_cycles must be positive", "MSHR_CONFIG")
    end
endfunction

task mshr_driver::run_phase(uvm_phase phase);
    drive_idle();
    wait (vif.rst_n === 1'b1);
    forever begin
        seq_item_port.get_next_item(req);
        wait (vif.rst_n === 1'b1);
        fork : request_or_reset
            begin
                drive_transaction(req);
            end
            begin
                @(negedge vif.rst_n);
                if (!cfg.allow_reset_cancellation) begin
                    `fatal("Active request reset requires cancellation enabled", "TB_RESET")
                end
                drive_idle();
            end
        join_any
        disable request_or_reset;
        seq_item_port.item_done();
    end
endtask

// 撤销上游使能并清空无效载荷及查询；内存、fillReady和replay.ready由各自代理驱动。
task mshr_driver::drive_idle();
    vif.alloc_en <= 0;
    vif.alloc_tag <= '0;
    vif.alloc_index <= '0;
    vif.alloc_way <= '0;
    vif.alloc_isWrite <= 0;
    vif.alloc_wData <= '0;
    vif.alloc_wordOff <= '0;
    vif.alloc_respId <= '0;
    vif.alloc_wbSlot <= '0;
    vif.alloc_hasWb <= 0;
    vif.merge_en <= 0;
    vif.merge_entry <= '0;
    vif.merge_isWrite <= 0;
    vif.merge_wData <= '0;
    vif.merge_wordOff <= '0;
    vif.merge_respId <= '0;
    vif.q0_tag <= '0;
    vif.q0_index <= '0;
    vif.q1_tag <= '0;
    vif.q1_index <= '0;
endtask

// 将transaction给出的两路独立查询送到接口；提交周期不把请求目标强加给查询口。
task mshr_driver::drive_queries(mshr_transaction item);
    vif.q0_tag <= item.q0Tag;
    vif.q0_index <= item.q0Index;
    vif.q1_tag <= item.q1Tag;
    vif.q1_index <= item.q1Index;
endtask

// 检查操作类型、索引范围和控制拍数；实际资源资格在提交前另行检查。
function void mshr_driver::check_transaction(mshr_transaction item);
    // 【防御性检查】确认调用方提供有效对象，避免空句柄被继续访问。
    if (item == null) begin
        `fatal("MSHR transaction can not be null", "MSHR_REQUEST")
    end
    // 【防御性检查】transaction操作码必须属于driver支持的类型。
    if ($isunknown(item.operation) || !(item.operation inside {MSHR_ALLOC, MSHR_MERGE, MSHR_QUERY, MSHR_IDLE})) begin
        `fatal("Unknown MSHR operation", "MSHR_REQUEST")
    end
    // 【激励合法性检查】查询与请求的set/way/word等字段不能超出接口范围。
    if ($unsigned(item.q0Index) >= NUM_SETS || $unsigned(item.q1Index) >= NUM_SETS) begin
        `fatal("Query set index is out of range", "MSHR_REQUEST")
    end
    if (item.operation inside {MSHR_ALLOC, MSHR_MERGE}) begin
        if ($unsigned(item.index) >= NUM_SETS || $unsigned(item.wordOff) >= WORDS_PER_BLOCK) begin
            `fatal("Request set index or word offset is out of range", "MSHR_REQUEST")
        end
        if (item.operation == MSHR_ALLOC && ($unsigned(item.way) >= NUM_WAYS ||
            (item.hasWb && $unsigned(item.wbSlot) >= WBB_ENTRIES))) begin
            `fatal("Allocation way or valid WBB slot is out of range", "MSHR_REQUEST")
        end
    end else if (item.cycles == 0) begin
        `fatal("Query/idle operations require at least one cycle", "MSHR_REQUEST")
    end
endfunction

// 分派一次Slot提交或查询/空闲操作；提交后撤销使能才返回，不等待内存及重放完成。
task mshr_driver::drive_transaction(mshr_transaction item);

    // 检查事务字段并清除上一次提交结果。
    check_transaction(item);
    item.selected_entry = -1;
    item.selected_slot = -1;
    if (item.reset_release_alloc) begin
        drive_reset_release_alloc(item);
        return;
    end
    if (item.operation inside {MSHR_ALLOC, MSHR_MERGE}) begin

        // 先查询并等待资源，再在同一下降沿驱动一次提交。
        prepare_request_query(item);
        wait_for_resources(item);
        drive_request(item);

        // 上升沿确认提交，下一下降沿撤销使能后才结束此项。
        @(vif.mon_cb);
        check_submission(item);
        @(negedge vif.clk);
        drive_idle();
    end else begin
        drive_nonrequest(item);
    end
endtask

// 先保持一个完整周期的目标查询，期间alloc/merge均为0，给资源判定提供稳定的组合输出。
// q1仅在准备/等待阶段临时查询请求块；真正提交时恢复transaction指定的独立查询地址。
task mshr_driver::prepare_request_query(mshr_transaction item);
    @(negedge vif.clk);
    if (vif.rst_n !== 1'b1) begin
        `fatal("Reset before preparing MSHR request", "MSHR_RESET")
    end
    drive_idle();
    vif.q0_tag <= item.q0Tag;
    vif.q0_index <= item.q0Index;
    vif.q1_tag <= item.tag;
    vif.q1_index <= item.index;
endtask

// 每次在下降沿读取已经更新的DUT状态；可提交时在同一下降沿返回，随后直接驱动单拍en。
// 不使用上一上升沿的旧m1判断，因为该沿可能已经接受响应并使目标进入不可合并的FILL。
task mshr_driver::wait_for_resources(mshr_transaction item);
    repeat (cfg.request_timeout_cycles) begin
        @(negedge vif.clk);
        if (vif.rst_n !== 1'b1) begin
            `fatal("Reset while waiting for MSHR resources", "MSHR_RESET")
        end
        if (request_ready(item)) begin
            return;
        end
    end
    `fatal($sformatf("MSHR request timed out: operation=%0d tag=0x%h index=%0d after %0d cycles",
        item.operation, item.tag, item.index, cfg.request_timeout_cycles), "MSHR_REQUEST_TIMEOUT")
endtask

// 使用当前q1目标查询、hasFree与lockMask判断资格；只在字段有效时读取Entry/Slot索引。
// 找到位置后把实际Entry/Slot写回transaction，供sequence及test保存本次提交身份。
function bit mshr_driver::request_ready(mshr_transaction item);
    int lock_index;

    // 先检查资源反馈及预查询地址，避免使用未知值或错地址的查询结果。
    if ($isunknown({vif.hasFree, vif.m1_hit})) begin
        `fatal("Unknown free-entry or match result", "MSHR_REQUEST")
    end
    if (vif.q1_tag !== item.tag || vif.q1_index !== item.index) begin
        `fatal("Request qualification query was changed unexpectedly", "MSHR_REQUEST")
    end

    // ALLOC检查块和way是否空闲；MERGE检查目标Entry阶段及Slot空间。
    if (item.operation == MSHR_ALLOC) begin
        lock_index = int'(item.index) * NUM_WAYS + int'(item.way);
        if ($isunknown(vif.lockMask[lock_index])) begin
            `fatal("Unknown allocation way lock", "MSHR_REQUEST")
        end
        if (!vif.hasFree || vif.m1_hit || vif.lockMask[lock_index]) begin
            return 0;
        end
        if ($isunknown(vif.freeEntry) || $unsigned(vif.freeEntry) >= MSHR_ENTRIES) begin
            `fatal("Invalid freeEntry for allocation", "MSHR_REQUEST")
        end
        item.selected_entry = int'(vif.freeEntry);
        item.selected_slot = 0;
    end else begin
        if (!vif.m1_hit) begin
            `fatal("Merge target is not allocated or has already completed", "MSHR_REQUEST")
        end
        if ($isunknown({vif.m1_entry, vif.m1_mergeable, vif.m1_slotFree}) ||
            $unsigned(vif.m1_entry) >= MSHR_ENTRIES) begin
            `fatal("Invalid merge target query result", "MSHR_REQUEST")
        end
        if (!vif.m1_mergeable) begin
            `fatal("Merge target no longer accepts slots", "MSHR_REQUEST")
        end
        if (!vif.m1_slotFree) begin
            return 0;
        end
        if ($isunknown(vif.m1_freeSlot) || $unsigned(vif.m1_freeSlot) >= MSHR_MAX_PENDING) begin
            `fatal("Invalid freeSlot for merge", "MSHR_REQUEST")
        end
        item.selected_entry = int'(vif.m1_entry);
        item.selected_slot = int'(vif.m1_freeSlot);
    end

    // 把真实选择返回给transaction，后续提交使用同一Entry。
    item.entry = ENTRY_WIDTH'(item.selected_entry);
    return 1;
endfunction

// 在最终资格检查的同一下降沿准备一次alloc或merge；到下一上升沿前没有其他状态更新。
// 两路en互斥，merge使用真实查询返回的Entry；payload来自sequence，driver不生成测试数据。
task mshr_driver::drive_request(mshr_transaction item);
    drive_queries(item);
    if (item.operation == MSHR_ALLOC) begin
        vif.alloc_en <= 1;
        vif.alloc_tag <= item.tag;
        vif.alloc_index <= item.index;
        vif.alloc_way <= item.way;
        vif.alloc_isWrite <= item.isWrite;
        vif.alloc_wData <= item.wData;
        vif.alloc_wordOff <= item.wordOff;
        vif.alloc_respId <= item.respId;
        vif.alloc_wbSlot <= item.wbSlot;
        vif.alloc_hasWb <= item.hasWb;
        vif.merge_en <= 0;
    end else begin
        vif.alloc_en <= 0;
        vif.merge_en <= 1;
        vif.merge_entry <= ENTRY_WIDTH'(item.selected_entry);
        vif.merge_isWrite <= item.isWrite;
        vif.merge_wData <= item.wData;
        vif.merge_wordOff <= item.wordOff;
        vif.merge_respId <= item.respId;
    end
endtask

// 在实际提交沿确认使能及Entry身份；查询口若仍指向目标，还检查沿前merge资格。
// 独立查询已改向其他块时，目标生命周期由共同的IO检查器核对，不误用其他块的m0/m1。
function void mshr_driver::check_submission(mshr_transaction item);
    if (vif.mon_cb.rst_n !== 1'b1) begin
        `fatal("Reset during MSHR submission", "MSHR_RESET")
    end
    if (item.operation == MSHR_ALLOC) begin
        if (vif.mon_cb.alloc_en !== 1'b1 || vif.mon_cb.merge_en !== 1'b0 ||
            vif.mon_cb.hasFree !== 1'b1 || $isunknown(vif.mon_cb.freeEntry) ||
            int'(vif.mon_cb.freeEntry) != item.selected_entry) begin
            `fatal("Allocation qualification changed before submission", "MSHR_REQUEST")
        end
    end else begin
        if (vif.mon_cb.merge_en !== 1'b1 || vif.mon_cb.alloc_en !== 1'b0 ||
            vif.mon_cb.merge_entry !== ENTRY_WIDTH'(item.selected_entry)) begin
            `fatal("Merge submission did not preserve its selected Entry", "MSHR_REQUEST")
        end
        if (item.q1Tag == item.tag && item.q1Index == item.index &&
            (vif.mon_cb.m1_hit !== 1'b1 || vif.mon_cb.m1_mergeable !== 1'b1 ||
            vif.mon_cb.m1_slotFree !== 1'b1 || vif.mon_cb.m1_entry !== ENTRY_WIDTH'(item.selected_entry) ||
            vif.mon_cb.m1_freeSlot !== SLOT_WIDTH'(item.selected_slot))) begin
            `fatal("Merge target changed before submission", "MSHR_REQUEST")
        end
    end
endfunction

// 保持纯查询或空闲指定数量的采样沿；期间不提交Slot，内存与填充/重放继续独立运行。
task mshr_driver::drive_nonrequest(mshr_transaction item);
    @(negedge vif.clk);
    drive_idle();
    if (item.idle_payload_enable) drive_invalid_payload(item);
    if (item.operation == MSHR_QUERY) begin
        drive_queries(item);
    end
    repeat (item.cycles) begin
        @(vif.mon_cb);
        if (vif.mon_cb.rst_n !== 1'b1) begin
            `fatal("Reset during MSHR query/idle", "MSHR_RESET")
        end
    end
    @(negedge vif.clk);
    drive_idle();
endtask

// 在alloc/merge使能保持0时扰动载荷，验证无效字段不会改变DUT状态。
task mshr_driver::drive_invalid_payload(mshr_transaction item);
    vif.alloc_tag <= item.tag;
    vif.alloc_index <= item.index;
    vif.alloc_way <= item.way;
    vif.alloc_isWrite <= item.isWrite;
    vif.alloc_wordOff <= item.wordOff;
    vif.alloc_wData <= item.wData;
    vif.alloc_respId <= item.respId;
    vif.alloc_hasWb <= item.hasWb;
    vif.alloc_wbSlot <= item.wbSlot;
    vif.merge_entry <= item.entry;
    vif.merge_isWrite <= item.isWrite;
    vif.merge_wordOff <= item.wordOff;
    vif.merge_wData <= item.wData;
    vif.merge_respId <= item.respId;
endtask

// 复位后空态专用alloc：首个下降沿准备，首个有效沿提交；资格只取真实hasFree/freeEntry。
task mshr_driver::drive_reset_release_alloc(mshr_transaction item);
    // 【激励合法性检查】只有显式标记的alloc可走此路径，查询/merge仍使用普通流程。
    if (item.operation != MSHR_ALLOC) begin
        `fatal("Reset release fast path requires alloc", "MSHR_RESET_INPUT")
    end
    @(negedge vif.clk);
    if (vif.hasFree !== 1'b1 || $isunknown(vif.freeEntry) || int'(vif.freeEntry) >= MSHR_ENTRIES) begin
        `fatal("No valid free Entry after reset", "MSHR_RESET_FREE")
    end
    item.selected_entry = vif.freeEntry;
    item.selected_slot = 0;
    drive_queries(item);
    drive_request(item);
    @(vif.mon_cb);
    check_submission(item);
    @(negedge vif.clk);
    drive_idle();
endtask
