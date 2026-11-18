class wbb_pending_response extends uvm_object;
    int unsigned id;
    realtime due_time;
    longint unsigned accepted_cycle;

    `uvm_object_utils(wbb_pending_response)

    function new(string name = "wbb_pending_response");
        super.new(name);
    endfunction


endclass

class wbb_memory_driver extends uvm_component;
    virtual wbb_interface vif;
    wbb_config cfg;
    wbb_memory_store memory;
    uvm_analysis_imp #(wbb_sample, wbb_memory_driver) monitor_export;
    protected wbb_pending_response pending[$];
    protected bit outstanding[int unsigned];
    protected longint unsigned cycle;
    protected bit reset_released;

    `uvm_component_utils(wbb_memory_driver)

    function new(string name = "wbb_memory_driver",
        uvm_component parent = null);
        super.new(name, parent);
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_export = new("monitor_export", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern function void write(wbb_sample tr);
    extern function bit is_idle();
    extern virtual function void check_phase(uvm_phase phase);

endclass

function void wbb_memory_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg) ||
        !uvm_config_db #(wbb_memory_store)::get(this, "", "memory", memory)) begin
        `fatal("Memory configuration/store not found")
    end
endfunction

// 消费 monitor 在上升沿取得的采样：先处理已握手的写响应，再接收本拍新的写请求。
// 响应握手时检查队首 ID、到期条件及响应晚于请求接收拍，然后出队并释放在途 ID。
// 写请求握手时更新实际内存，记录 ID、到期时间和接收周期，供 run_phase 后续驱动响应。
function void wbb_memory_driver::write(wbb_sample tr);
    wbb_pending_response response;
    int unsigned id;
    if (tr.rst_n !== 1'b1) begin
        if (reset_released) begin
            `fatal("Mid-run reset is unsupported", "TB_RESET")
        end
        return;
    end
    reset_released = 1;
    cycle++;
    if ($isunknown({tr.send_valid, tr.send_ready, tr.memWriteResp_valid, tr.memWriteResp_ready})) begin
        `fatal("Memory channel control contains X/Z", "MEM_PROTOCOL")
    end
    if (tr.memWriteResp_valid && tr.memWriteResp_ready) begin
        if ($isunknown(tr.memWriteResp_payload_id) || pending.size() == 0) begin
            `fatal("Write response without a pending request", "MEM_PROTOCOL")
        end
        id = tr.memWriteResp_payload_id;
        if (id != pending[0].id || !outstanding.exists(id) ||
            $realtime < pending[0].due_time || cycle <= pending[0].accepted_cycle) begin
            `fatal("Unexpected or premature memory response", "MEM_PROTOCOL")
        end
        response = pending.pop_front();
        outstanding.delete(id);
    end
    if (tr.send_valid && tr.send_ready) begin
        if ($isunknown({tr.send_payload_id, tr.send_payload_addr, tr.send_payload_wData})) begin
            `fatal("Unknown memory write payload", "MEM_PROTOCOL")
        end
        id = tr.send_payload_id;
        if (id >= WBB_ENTRIES || outstanding.exists(id) || pending.size() >= cfg.mem_max_pending) begin
            `fatal("Invalid/duplicate write ID or pending queue overflow", "MEM_PROTOCOL")
        end
        // Actual storage is driven exclusively by DUT handshakes.
        memory.write_actual(tr.send_payload_addr, tr.send_payload_wData);
        response = wbb_pending_response::type_id::create("response");
        response.id = id;
        response.due_time = $realtime + cfg.mem_write_latency_ns;
        response.accepted_cycle = cycle;
        pending.push_back(response);
        outstanding[id] = 1;
    end
endfunction

task wbb_memory_driver::run_phase(uvm_phase phase);
    vif.send_ready <= 0;
    vif.memWriteResp_valid <= 0;
    vif.memWriteResp_payload_id <= '0;
    wait (vif.rst_n === 1'b1);
    forever begin
        @(negedge vif.clk);
        // The front entry stays queued until its actual response handshake.
        vif.send_ready <= (pending.size() < cfg.mem_max_pending);
        if (pending.size() > 0 && $realtime >= pending[0].due_time) begin
            vif.memWriteResp_valid <= 1;
            vif.memWriteResp_payload_id <= BUS_ID_WIDTH'(pending[0].id);
        end else begin
            vif.memWriteResp_valid <= 0;
            vif.memWriteResp_payload_id <= '0;
        end
    end
endtask

// 查询待响应队列和在途 ID 表是否均已清空，供环境判断内存侧是否完成排空。
function bit wbb_memory_driver::is_idle();
    return pending.size() == 0 && outstanding.num() == 0;
endfunction

function void wbb_memory_driver::check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!is_idle()) begin
        `error("Memory responses/IDs did not drain", "MEM_DRAIN")
    end
endfunction
