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
    extern task drive_reserve(wbb_transaction tr, output logic [SLOT_WIDTH-1:0] slot);
    extern task wait_reserve_success(wbb_transaction tr, output logic [SLOT_WIDTH-1:0] slot);
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

// 串联一笔完整写回事务：检查输入、预留槽位，再向该槽 push 数据。
// push 撤销后返回，由 run_phase 调用 item_done()；不等待内存写响应。
task wbb_driver::drive_transaction(wbb_transaction tr);
    logic [SLOT_WIDTH-1:0] slot;

    check_transaction(tr);
    drive_reserve(tr, slot);
    drive_push(tr, slot);
endtask

// 检查 transaction 非空，以及写回地址和两个查询地址满足块对齐要求；不消耗仿真时间。
function void wbb_driver::check_transaction(wbb_transaction tr);
    if (tr == null) begin
        `fatal("Writeback transaction can not be null")
    end
    if ((tr.addr % BLOCK_SIZE) != 0 || (tr.q0Addr % BLOCK_SIZE) != 0 ||
        (tr.q1Addr % BLOCK_SIZE) != 0) begin
        `fatal("Writeback and query addresses must be block aligned", "WBB_ALIGNMENT")
    end
endfunction

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

// 在预留成功后的下降沿撤销 reserve 并驱动 push，下一上升沿将整行数据交给已预留槽。
// 两个查询地址继续保持；push 采样完成后的下降沿恢复空闲，随后返回。
task wbb_driver::drive_push(wbb_transaction tr, logic [SLOT_WIDTH-1:0] slot);
    @(negedge vif.clk);
    if (vif.rst_n !== 1'b1) begin
        `fatal("Reset between reserve and push", "WBB_RESET")
    end
    vif.reserve_en <= 0;
    vif.reserve_addr <= '0;
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
