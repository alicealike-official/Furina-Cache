class wbb_monitor extends uvm_monitor;
    virtual wbb_interface vif;
    uvm_analysis_port #(wbb_sample) monitor_port;
    `uvm_component_utils(wbb_monitor)

    function new(string name = "wbb_monitor",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_port = new("monitor_port", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
endclass

function void wbb_monitor::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
endfunction

task wbb_monitor::run_phase(uvm_phase phase);
    forever begin
        wbb_sample sample;
        @(vif.mon_cb);
        sample = wbb_sample::type_id::create("tr");

        // -------------------- 复位状态 --------------------
        // rst_n 由 TB 提供；predictor 据此复位 C++ WBB 模型，或处理复位后的有效采样。
        sample.rst_n = vif.mon_cb.rst_n;

        // -------------------- 预留请求与容量反馈 --------------------
        // reserve_en/addr 为上游输入，predictor 将它们送入 C++ WBB 模型。
        // reserveOk/reserveSlot/full 为 DUT 输出，scoreboard 用实际值与模型预测比较，并统计预留和满状态。
        sample.reserve_en = vif.mon_cb.reserve_en;
        sample.reserve_addr = vif.mon_cb.reserve_addr;
        sample.reserveOk = vif.mon_cb.reserveOk;
        sample.reserveSlot = vif.mon_cb.reserveSlot;
        sample.full = vif.mon_cb.full;

        // -------------------- 已预留槽的整行装载 --------------------
        // push_en/slot/line 为上游输入，predictor 用它们更新 C++ WBB 中对应槽的数据。
        // scoreboard 统计 push 次数；实际稀疏内存等到下面的 send 握手时才写入。
        sample.push_en = vif.mon_cb.push_en;
        sample.push_slot = vif.mon_cb.push_slot;
        sample.push_line = vif.mon_cb.push_line;

        // -------------------- WBB 发往内存的写请求 --------------------
        // valid/addr/wData/id 由 DUT 输出，ready 由 memory driver 驱动。
        // memory driver 在实际握手时写入实际稀疏内存并登记待响应事务。
        // predictor 将 ready 送入模型；scoreboard 比较发送预测与实际输出，并检查反压保持。
        sample.send_valid = vif.mon_cb.send_valid;
        sample.send_ready = vif.mon_cb.send_ready;
        sample.send_payload_addr = vif.mon_cb.send_payload_addr;
        sample.send_payload_wData = vif.mon_cb.send_payload_wData;
        sample.send_payload_id = vif.mon_cb.send_payload_id;

        // -------------------- 内存返回的写完成响应 --------------------
        // valid/id 由 memory driver 驱动，ready 由 DUT 输出。
        // 握手后 memory driver 移除待响应记录，predictor 将握手事件和 ID 送入 C++ WBB 以释放槽位。
        // scoreboard 使用这组采样统计响应，并检查 DUT 的响应 ready。
        sample.memWriteResp_valid = vif.mon_cb.memWriteResp_valid;
        sample.memWriteResp_ready = vif.mon_cb.memWriteResp_ready;
        sample.memWriteResp_payload_id = vif.mon_cb.memWriteResp_payload_id;

        // -------------------- 两个独立的地址查询口 --------------------
        // q0Addr/q1Addr 为上游输入，predictor 将查询地址送入 C++ WBB 模型。
        // q0Same/q1Same 为 DUT 的实际匹配结果，通过 actual_sample 交给 scoreboard 与预测结果比较。
        sample.q0Addr = vif.mon_cb.q0Addr;
        sample.q1Addr = vif.mon_cb.q1Addr;
        sample.q0Same = vif.mon_cb.q0Same;
        sample.q1Same = vif.mon_cb.q1Same;

        // 将本拍完整快照同时发布给 memory driver 和 predictor，触发各自的 write(sample)。
        // predictor 再把该快照绑定到 wbb_compare_item.actual_sample，连同期望值送给 scoreboard。
        monitor_port.write(sample);
    end
endtask
