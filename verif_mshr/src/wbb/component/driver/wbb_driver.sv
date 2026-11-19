class wbb_driver extends uvm_driver #(wbb_transaction);
    virtual wbb_interface vif;
    wbb_config cfg;
    `uvm_component_utils(wbb_driver)

    function new(string name = "wbb_driver",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern task drive_idle();
    extern task drive_transaction(wbb_transaction tr);
    extern function void check_transaction(wbb_transaction tr);
    extern function void require_delayed_mode();
    extern function void check_batch(wbb_batch_transaction batch);
    extern task drive_nonwriteback(wbb_transaction tr);
    extern task drive_batch(wbb_batch_transaction batch);
    extern task hold_batch(wbb_batch_transaction batch);
    extern task drive_reserve(wbb_transaction tr, output logic [SLOT_WIDTH-1:0] slot);
    extern task wait_reserve_success(wbb_transaction tr, output logic [SLOT_WIDTH-1:0] slot);
    extern task wait_before_push(wbb_transaction tr);
    extern task drive_push(wbb_transaction tr, logic [SLOT_WIDTH-1:0] slot);
endclass

function void wbb_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg)) begin
        `fatal("wbb_config not found")
    end
    if (cfg.reserve_timeout_cycles == 0) begin
        `fatal("reserve_timeout_cycles must be positive")
    end
endfunction

// 撤销上游 reserve/push，使载荷和查询口恢复空闲值；不等待时钟沿。
// 内存侧 ready 和响应由 memory driver 独立驱动。
task wbb_driver::drive_idle();
    vif.reserve_en <= '0;
    vif.reserve_addr <= '0;
    vif.push_en <= '0;
    vif.push_slot <= '0;
    vif.push_line <= '0;
    vif.q0Addr <= '0;
    vif.q1Addr <= '0;
endtask

task wbb_driver::run_phase(uvm_phase phase);
    drive_idle();
    wait (vif.rst_n === 1'b1);
    forever begin
        seq_item_port.get_next_item(req);
        drive_transaction(req);
        seq_item_port.item_done();
    end
endtask

// 根据操作类型分派：普通写回完成 reserve/push，查询或空闲保持指定拍数，批量写回先全部预留再全部 push。
// 所有操作都由同一个 driver 驱动上游信号，结束后才 item_done，不等待内存响应。
task wbb_driver::drive_transaction(wbb_transaction tr);
    logic [SLOT_WIDTH-1:0] slot;
    wbb_batch_transaction batch;

    check_transaction(tr);
    if ($cast(batch, tr)) begin
        check_batch(batch);
        drive_batch(batch);
    end else if (tr.operation == WBB_WRITEBACK) begin
        drive_reserve(tr, slot);
        drive_push(tr, slot);
    end else begin
        drive_nonwriteback(tr);
    end
endtask

// 检查操作类型、地址对齐和等待拍数；普通写回延迟超过1拍时，必须显式允许延迟 push。
function void wbb_driver::check_transaction(wbb_transaction tr);
    if (tr == null) begin
        `fatal("Writeback transaction can not be null")
    end
    if ($isunknown(tr.operation) || !(tr.operation inside {WBB_WRITEBACK, WBB_QUERY, WBB_IDLE})) begin
        `fatal("Unknown WBB operation", "WBB_OPERATION")
    end
    if ((tr.operation == WBB_WRITEBACK && (tr.addr % BLOCK_SIZE) != 0) || (tr.q0Addr % BLOCK_SIZE) != 0 ||
        (tr.q1Addr % BLOCK_SIZE) != 0) begin
        `fatal("Writeback and query addresses must be block aligned", "WBB_ALIGNMENT")
    end
    if (tr.operation == WBB_WRITEBACK) begin
        if ($isunknown(tr.push_delay_cycles) || tr.push_delay_cycles == 0) begin
            `fatal("push_delay_cycles must be at least one", "WBB_PUSH_DELAY")
        end
        if (tr.push_delay_cycles > 1) begin
            require_delayed_mode();
        end
    end else if ($isunknown(tr.cycles) || tr.cycles == 0) begin
        `fatal("Query/idle operations require at least one sampled cycle", "WBB_OPERATION_CYCLES")
    end
endfunction

// 延迟 push 必须同时启用编译模式和运行配置，避免上游驱动与严格下一拍断言使用不同契约。
function void wbb_driver::require_delayed_mode();
`ifndef WBB_ALLOW_DELAYED_PUSH
    `fatal("Compile with WBB_ALLOW_DELAYED_PUSH before delaying push", "WBB_DELAY_MODE")
`endif
    if (!cfg.allow_delayed_push) begin
        `fatal("allow_delayed_push must be enabled for this operation", "WBB_DELAY_MODE")
    end
endfunction

// 批量操作必须包含1到N笔不同地址的普通写回；每笔只提供数据，等待拍数由批次统一控制。
// 拒绝嵌套批次和单笔延迟设置，避免一笔数据到底何时 push 出现两种解释。
function void wbb_driver::check_batch(wbb_batch_transaction batch);
    wbb_batch_transaction nested;

    require_delayed_mode();
    if (batch.operation != WBB_WRITEBACK || batch.push_delay_cycles != 1 ||
        batch.entries.size() == 0 || batch.entries.size() > WBB_ENTRIES ||
        $isunknown(batch.hold_cycles) || batch.hold_cycles == 0) begin
        `fatal("Batch requires 1..WBB_ENTRIES writebacks and positive hold_cycles", "WBB_BATCH")
    end
    foreach (batch.entries[i]) begin
        check_transaction(batch.entries[i]);
        if ($cast(nested, batch.entries[i]) || batch.entries[i].operation != WBB_WRITEBACK ||
            batch.entries[i].push_delay_cycles != 1) begin
            `fatal("Batch entries must be ordinary writebacks with the default push delay", "WBB_BATCH")
        end
        for (int j = 0; j < i; j++) begin
            if (batch.entries[i].addr == batch.entries[j].addr) begin
                `fatal("Batch writeback addresses must be distinct", "WBB_BATCH")
            end
        end
    end
endfunction

// 保持独立查询或空闲状态指定数量的上升沿；整个操作期间 reserve/push 均为0。
// 查询地址由 transaction 给出，driver 不生成测试数据或预测查询结果。
task wbb_driver::drive_nonwriteback(wbb_transaction tr);
    @(negedge vif.clk);
    drive_idle();
    if (tr.operation == WBB_QUERY) begin
        vif.q0Addr <= tr.q0Addr;
        vif.q1Addr <= tr.q1Addr;
    end
    repeat (tr.cycles) begin
        @(vif.mon_cb);
        if (vif.mon_cb.rst_n !== 1'b1) begin
            `fatal("Reset during query/idle operation", "WBB_RESET")
        end
    end
    @(negedge vif.clk);
    drive_idle();
endtask

// 先为全部完整事务预留槽，再等待，最后按原顺序逐笔 push；不出现 reserve/push 同拍。
// 所有槽号都使用真实 reserve 成功时的返回值，整批 push 完成后才返回给 run_phase。
task wbb_driver::drive_batch(wbb_batch_transaction batch);
    logic [SLOT_WIDTH-1:0] slots[$];
    logic [SLOT_WIDTH-1:0] slot;

    foreach (batch.entries[i]) begin
        drive_reserve(batch.entries[i], slot);
        slots.push_back(slot);
    end
    hold_batch(batch);
    foreach (batch.entries[i]) begin
        drive_push(batch.entries[i], slots[i]);
    end
endtask

// 最后一笔 reserve 成功后撤销请求，使用 batch 的查询地址等待 hold_cycles 个采样拍。
// 首个 push 在最后一次 reserve 后的第 hold_cycles+1 拍采样；等待时不会多发 reserve。
task wbb_driver::hold_batch(wbb_batch_transaction batch);
    @(negedge vif.clk);
    drive_idle();
    vif.q0Addr <= batch.q0Addr;
    vif.q1Addr <= batch.q1Addr;
    repeat (batch.hold_cycles) begin
        @(vif.mon_cb);
        if (vif.mon_cb.rst_n !== 1'b1) begin
            `fatal("Reset while holding batch reservations", "WBB_RESET")
        end
    end
endtask

// 在下降沿驱动预留请求及两个查询地址，再等待成功并返回实际槽号。
// 成功后仍保持 reserve_en，交由紧随的 drive_push 在下一下降沿撤销。
task wbb_driver::drive_reserve(wbb_transaction tr, output logic [SLOT_WIDTH-1:0] slot);
    @(negedge vif.clk);
    if (vif.rst_n !== 1'b1) begin
        `fatal("Mid-transaction reset is not supported", "WBB_RESET")
    end
    vif.reserve_en <= 1;
    vif.reserve_addr <= tr.addr;
    vif.q0Addr <= tr.q0Addr;
    vif.q1Addr <= tr.q1Addr;
    wait_reserve_success(tr, slot);
endtask

// 逐拍等待 reserve_en && reserveOk，检查复位、未知值和槽号合法性，并保存成功时的槽号。
// 在 reserve_timeout_cycles 拍内未成功时报 fatal；该 task 只采样，不修改接口输入。
task wbb_driver::wait_reserve_success(wbb_transaction tr, output logic [SLOT_WIDTH-1:0] slot);
    bit reserved;

    reserved = 0;
    repeat (cfg.reserve_timeout_cycles) begin
        @(vif.mon_cb);
        if (vif.mon_cb.rst_n !== 1'b1) begin
            `fatal("Reset while waiting for WBB reservation", "WBB_RESET")
        end
        if ($isunknown(vif.mon_cb.reserveOk)) begin
            `fatal("reserveOk contains X/Z", "WBB_RESERVE")
        end
        if (vif.mon_cb.reserve_en && vif.mon_cb.reserveOk) begin
            if ($isunknown(vif.mon_cb.reserveSlot) || int'(vif.mon_cb.reserveSlot) >= WBB_ENTRIES) begin
                `fatal("Invalid reserved slot", "WBB_RESERVE")
            end
            slot = vif.mon_cb.reserveSlot;
            reserved = 1;
            break;
        end
    end
    if (!reserved) begin
        `fatal($sformatf("Reservation timed out after %0d cycles at address 0x%h",
            cfg.reserve_timeout_cycles, tr.addr), "WBB_RESERVE_TIMEOUT")
    end
endtask

// 预留成功后先撤销 reserve；L=1时立刻准备下一拍push，L>1时额外等待L-1个采样拍。
// 返回时正处于目标 push 拍之前的下降沿，因此 E[k] 预留会在 E[k+L] 完成 push。
task wbb_driver::wait_before_push(wbb_transaction tr);
    @(negedge vif.clk);
    if (vif.rst_n !== 1'b1) begin
        `fatal("Reset between reserve and push", "WBB_RESET")
    end
    vif.reserve_en <= 0;
    vif.reserve_addr <= '0;
    vif.push_en <= 0;
    vif.push_slot <= '0;
    vif.push_line <= '0;
    vif.q0Addr <= tr.q0Addr;
    vif.q1Addr <= tr.q1Addr;
    repeat (tr.push_delay_cycles - 1) begin
        @(vif.mon_cb);
        if (vif.mon_cb.rst_n !== 1'b1) begin
            `fatal("Reset while delaying WBB push", "WBB_RESET")
        end
        @(negedge vif.clk);
    end
endtask

// 在已准备好的下降沿驱动整行push，下一上升沿采样，随后下降沿恢复空闲。
// 普通事务默认保持原先严格下一拍时序；批量事务调用本task时，所有reserve已经完成。
task wbb_driver::drive_push(wbb_transaction tr, logic [SLOT_WIDTH-1:0] slot);
    wait_before_push(tr);
    vif.push_en <= 1;
    vif.push_slot <= slot;
    vif.push_line <= tr.line_data;

    @(vif.mon_cb);
    if (vif.mon_cb.rst_n !== 1'b1) begin
        `fatal("Reset during WBB push", "WBB_RESET")
    end
    @(negedge vif.clk);
    drive_idle();
endtask
