class wbb_pending_response extends uvm_object;
    int unsigned id;
    // 记录请求在哪一拍接受，以及最早允许在哪一拍返回响应，均以 monitor 的上升沿计数。
    longint unsigned due_cycle;
    longint unsigned accepted_cycle;

    `uvm_object_utils(wbb_pending_response)

    function new(string name = "wbb_pending_response");
        super.new(name);
    endfunction

endclass

class wbb_memory_driver extends uvm_component;
    virtual wbb_interface vif;
    wbb_config cfg;
    // C++ 稀疏内存的 SV 封装句柄，通过 DPI 访问独立的实际/期望内存实例。
    // 存储实现见 RefModel/MEM/SparseMemory.hpp，SV 封装见 model/wbb_memory_store.sv。
    wbb_memory_store memory;
    uvm_analysis_imp #(wbb_sample, wbb_memory_driver) monitor_export;
    protected wbb_pending_response pending[$];
    // 已经在接口呈现的响应；握手前始终保留同一对象，不受后续顺序配置变化影响。
    protected wbb_pending_response active_response;
    protected bit outstanding[int unsigned];
    protected longint unsigned cycle = 0;
    protected bit reset_released;

    `uvm_component_utils(wbb_memory_driver)

    function new(string name = "wbb_memory_driver",
        uvm_component parent = null);
        super.new(name, parent);
        // 【防御性检查】组件必须接入UVM层级，避免空父组件造成环境构建错误。
        if (parent == null) begin
            `fatal("This component's parent can not be null!!")
        end
        monitor_export = new("monitor_export", this);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_phase(uvm_phase phase);
    extern function void write(wbb_sample sample);
    extern function bit prepare_sample(wbb_sample sample);
    extern function void process_response(wbb_sample sample);
    extern function void process_request(wbb_sample sample);
    extern function void check_configuration();
    extern function int find_pending_index(int unsigned id);
    extern function int choose_response_index();
    extern function int unsigned choose_latency_cycles();
    extern task drive_idle();
    extern task drive_memory_outputs();
    extern task drive_send_ready();
    extern task drive_response();
    extern function bit is_idle();
    extern virtual function void check_phase(uvm_phase phase);

endclass

function void wbb_memory_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual wbb_interface)::get(this, "", "wbb_vif", vif)) begin
        `fatal("wbb_interface not found")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(wbb_config)::get(this, "", "wbb_config", cfg) ||
        !uvm_config_db #(wbb_memory_store)::get(this, "", "memory", memory)) begin
        `fatal("Memory configuration/store not found")
    end
    check_configuration();
endfunction

// 检查内存调度参数；运行时控制也会经过这里，防止非法概率、延迟范围或响应ID被静默使用。
function void wbb_memory_driver::check_configuration();
    // 【防御性检查】以下整段校验内存代理的延迟、容量、随机范围和响应策略配置。
    if (cfg.mem_write_latency_cycles == 0 || $isunknown(cfg.mem_write_latency_cycles)) begin
        `fatal("mem_write_latency_cycles must be at least one cycle", "MEM_CONFIG")
    end
    if (cfg.mem_max_pending == 0 || $isunknown(cfg.mem_max_pending) ||
        cfg.mem_ready_percent > 100 || $isunknown(cfg.mem_ready_percent)) begin
        `fatal("Memory capacity must be positive and ready percentage must be 0..100", "MEM_CONFIG")
    end
    if (cfg.mem_random_latency &&
        ($isunknown({cfg.mem_min_latency_cycles, cfg.mem_max_latency_cycles}) ||
        cfg.mem_min_latency_cycles == 0 || cfg.mem_max_latency_cycles < cfg.mem_min_latency_cycles)) begin
        `fatal("Random response latency requires 1 <= minimum <= maximum", "MEM_CONFIG")
    end
    if ($isunknown(cfg.mem_response_order) ||
        !(cfg.mem_response_order inside {WBB_MEM_FIFO, WBB_MEM_LIFO, WBB_MEM_RANDOM, WBB_MEM_SELECTED})) begin
        `fatal("Unknown memory response ordering policy", "MEM_CONFIG")
    end
    if (cfg.mem_response_order == WBB_MEM_SELECTED &&
        ($isunknown(cfg.mem_selected_response_id) || cfg.mem_selected_response_id >= WBB_ENTRIES)) begin
        `fatal("Selected memory response ID is outside the WBB slot range", "MEM_CONFIG")
    end
endfunction

// 消费 monitor 的本拍采样，先检查采样有效性，再处理响应释放和新请求接收。
// 同拍先释放旧响应、再接收新请求，使容量和在途 ID 的检查使用已释放后的状态。
function void wbb_memory_driver::write(wbb_sample sample);
    if (!prepare_sample(sample)) begin
        return;
    end
    process_response(sample);
    process_request(sample);
endfunction

// 启动复位期间跳过采样，运行中再次复位时报错；正常采样更新周期计数并检查握手控制无 X/Z。
// 返回 1 表示本拍可继续处理，每个有效非复位采样只在此处递增一次 cycle。
function bit wbb_memory_driver::prepare_sample(wbb_sample sample);
    if (sample.rst_n !== 1'b1) begin
        if (reset_released) begin
            `fatal("Mid-run reset is unsupported", "TB_RESET")
        end
        return 0;
    end
    reset_released = 1;
    cycle++;
    if ($isunknown({sample.send_valid, sample.send_ready, sample.memWriteResp_valid, sample.memWriteResp_ready})) begin
        `fatal("Memory channel control contains X/Z", "MEM_PROTOCOL")
    end
    return 1;
endfunction

// 响应握手时，核对之前已经锁定的响应、其ID及等待拍数，再删除对应待响应记录。
// 乱序模式按实际ID找到记录，不把它错误地当成队首；没有握手就不删除或重新选择响应。
function void wbb_memory_driver::process_response(wbb_sample sample);
    wbb_pending_response response;
    int unsigned id;
    int index;

    if (sample.memWriteResp_valid && sample.memWriteResp_ready) begin
        if ($isunknown(sample.memWriteResp_payload_id) || active_response == null) begin
            `fatal("Write response without a pending request", "MEM_PROTOCOL")
        end
        id = sample.memWriteResp_payload_id;
        index = find_pending_index(id);
        if (index < 0) begin
            `fatal("Response ID is not present in the pending queue", "MEM_PROTOCOL")
        end
        if (id != active_response.id || pending[index] != active_response || !outstanding.exists(id) ||
            cycle < active_response.due_cycle || cycle <= active_response.accepted_cycle) begin
            `fatal("Unexpected or premature memory response", "MEM_PROTOCOL")
        end

        // 归属和周期检查通过后，再移除对应响应及在途ID。
        response = active_response;
        pending.delete(index);
        outstanding.delete(id);
        active_response = null;
        `info_high($sformatf("id=%0d accepted_cycle=%0d response_cycle=%0d latency_cycles=%0d configured_cycles=%0d",
            id, response.accepted_cycle, cycle, cycle - response.accepted_cycle,
            response.due_cycle - response.accepted_cycle), "MEM_RESPONSE_TIMING")
    end
endfunction

// 写请求握手时，检查载荷、ID 合法性和队列容量，然后将整行数据写入实际内存。
// 请求在第 k 拍接受，就登记第 k+L 拍为最早响应拍；L 来自周期数配置，不换算成 ns。
function void wbb_memory_driver::process_request(wbb_sample sample);
    wbb_pending_response response;
    int unsigned id;

    if (sample.send_valid && sample.send_ready) begin
        if ($isunknown({sample.send_payload_id, sample.send_payload_addr, sample.send_payload_wData})) begin
            `fatal("Unknown memory write payload", "MEM_PROTOCOL")
        end
        id = sample.send_payload_id;
        if (id >= WBB_ENTRIES || outstanding.exists(id) || pending.size() >= cfg.mem_max_pending) begin
            `fatal("Invalid/duplicate write ID or pending queue overflow", "MEM_PROTOCOL")
        end
        // 调用 model/wbb_memory_store.sv 的 SV 封装 write_actual()。
        // 封装经 sparse_mem_write_line DPI 调用 C++ SparseMemory::writeLine()，写入实际内存。
        memory.write_actual(sample.send_payload_addr, sample.send_payload_wData);
        response = wbb_pending_response::type_id::create("response");
        response.id = id;
        response.due_cycle = cycle + choose_latency_cycles();
        response.accepted_cycle = cycle;
        pending.push_back(response);
        outstanding[id] = 1;
    end
endfunction

// 根据实际在途ID查找待响应记录的位置；没有该ID时返回-1，调用方决定是等待还是报错。
function int wbb_memory_driver::find_pending_index(int unsigned id);
    foreach (pending[index]) begin
        if (pending[index].id == id) begin
            return index;
        end
    end
    return -1;
endfunction

// 只从下一采样拍已经到期的请求中选择响应；暂停响应时不开始新响应。
// FIFO等待原队首到期；LIFO取最后一个到期请求；随机策略在到期集合中选；指定策略只等待指定ID。
function int wbb_memory_driver::choose_response_index();
    int candidates[$];
    int index;

    // 响应暂停或队列为空时不开始新响应。
    if (!cfg.mem_response_enable || pending.size() == 0) begin
        return -1;
    end

    // FIFO/指定ID直接选择；其他策略先收集已经到期的候选。
    case (cfg.mem_response_order)
        WBB_MEM_FIFO: begin
            return cycle + 1 >= pending[0].due_cycle ? 0 : -1;
        end
        WBB_MEM_SELECTED: begin
            index = find_pending_index(cfg.mem_selected_response_id);
            if (index < 0) begin
                return -1;
            end
            if (cycle + 1 >= pending[index].due_cycle) begin
                return index;
            end
            return -1;
        end
        default: begin
            foreach (pending[pending_index]) begin
                if (cycle + 1 >= pending[pending_index].due_cycle) begin
                    candidates.push_back(pending_index);
                end
            end

            // 没有到期项则继续等待，否则按LIFO或随机策略选择。
            if (candidates.size() == 0) begin
                return -1;
            end
            if (cfg.mem_response_order == WBB_MEM_LIFO) begin
                return candidates[$];
            end
            return candidates[$urandom_range(candidates.size() - 1, 0)];
        end
    endcase
endfunction

// 为当前新请求确定响应等待拍数；固定模式不消耗随机数，随机模式在配置范围内抽取一次。
function int unsigned wbb_memory_driver::choose_latency_cycles();
    check_configuration();
    if (cfg.mem_random_latency) begin
        return $urandom_range(cfg.mem_max_latency_cycles, cfg.mem_min_latency_cycles);
    end
    return cfg.mem_write_latency_cycles;
endfunction

task wbb_memory_driver::run_phase(uvm_phase phase);
    drive_idle();
    wait (vif.rst_n === 1'b1);
    forever begin
        @(negedge vif.clk);
        drive_memory_outputs();
    end
endtask

// 初始化内存侧的 ready 和响应输出，等待启动复位结束后再接收写请求。
task wbb_memory_driver::drive_idle();
    vif.send_ready <= 0;
    vif.memWriteResp_valid <= 0;
    vif.memWriteResp_payload_id <= '0;
endtask

// 在下降沿应用当前内存策略，分别准备下一上升沿使用的ready和响应输出。
task wbb_memory_driver::drive_memory_outputs();
    check_configuration();
    drive_send_ready();
    drive_response();
endtask

// 只有接收开关打开且待响应容量未满时才允许ready；随机模式可在此基础上插入背压。
task wbb_memory_driver::drive_send_ready();
    bit ready;

    ready = cfg.mem_send_enable && pending.size() < cfg.mem_max_pending;
    if (ready && cfg.mem_random_ready) begin
        ready = $urandom_range(99, 0) < cfg.mem_ready_percent;
    end
    vif.send_ready <= ready;
endtask

// 尚未呈现响应时才按策略选择；选中后锁住该对象，直到process_response观察到真实握手。
// cycle是刚结束的采样拍，因此使用cycle+1判断下一拍是否到期，保持准确的L拍响应语义。
// 即使中途关闭响应开关、改变顺序或加入新请求，已呈现的valid和ID也不能撤销或改变。
task wbb_memory_driver::drive_response();
    int index;

    // 尚未呈现响应时才选择新记录，已挂起的响应继续保持。
    if (active_response == null) begin
        index = choose_response_index();
        if (index >= 0) begin
            active_response = pending[index];
        end
    end

    // 把锁定记录驱动到下一采样沿；没有响应时才撤销valid。
    if (active_response != null) begin
        vif.memWriteResp_valid <= 1;
        vif.memWriteResp_payload_id <= BUS_ID_WIDTH'(active_response.id);
    end else begin
        vif.memWriteResp_valid <= 0;
        vif.memWriteResp_payload_id <= cfg.idle_response_id;
    end
endtask

// 检查待响应队列、在途ID和已经呈现的响应是否都已清空，供环境判断内存侧是否完成。
function bit wbb_memory_driver::is_idle();
    return pending.size() == 0 && outstanding.num() == 0 && active_response == null;
endfunction

function void wbb_memory_driver::check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!is_idle()) begin
        `error("Memory responses/IDs did not drain", "MEM_DRAIN")
    end
endfunction
