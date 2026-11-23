class mshr_pending_read extends uvm_object;
    int unsigned id;
    bit [ADDR_WIDTH-1:0] addr;
    // 读请求接受时从 C++ 稀疏内存取出的快照，响应等待期间不再次读内存。
    bit [LINE_WIDTH-1:0] data;
    longint unsigned accepted_cycle;
    longint unsigned due_cycle;

    `uvm_object_utils(mshr_pending_read)

    function new(string name = "mshr_pending_read");
        super.new(name);
    endfunction

endclass

class mshr_memory_driver extends uvm_component;
    virtual mshr_interface vif;
    mshr_config cfg;
    // C++ SparseMemory 的 SV 封装，定义在 model/mshr_memory_store.sv；实际模型见 RefModel/MEM/SparseMemory.hpp。
    mshr_memory_store memory;
    uvm_analysis_imp #(mshr_sample, mshr_memory_driver) monitor_export;
    int unsigned request_count;
    int unsigned response_count;

    protected mshr_pending_read pending[$];
    // 已经呈现到响应接口的对象；握手前不能因开关变化或新请求到达而替换。
    protected mshr_pending_read active_response;
    protected bit outstanding[int unsigned];
    protected longint unsigned cycle = 0;

    `uvm_component_utils(mshr_memory_driver)

    function new(string name = "mshr_memory_driver",
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
    extern virtual function void check_phase(uvm_phase phase);
    extern function void check_configuration();
    extern function void write(mshr_sample sample);
    extern function bit prepare_sample(mshr_sample sample);
    extern function void reset_bookkeeping();
    extern function void process_response(mshr_sample sample);
    extern function void process_request(mshr_sample sample);
    extern task drive_idle();
    extern task drive_memory_outputs();
    extern task drive_request_ready();
    extern task drive_response();
    extern function bit is_idle();

endclass

function void mshr_memory_driver::build_phase(uvm_phase phase);
    super.build_phase(phase);
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(virtual mshr_interface)::get(this, "", "mshr_vif", vif) || vif == null) begin
        `fatal("mshr_interface not found", "MSHR_MEM_CONFIG")
    end
    // 【防御性检查】确认上层传入所需配置、接口或模型封装；这是环境依赖检查。
    if (!uvm_config_db #(mshr_config)::get(this, "", "mshr_config", cfg) || cfg == null ||
        !uvm_config_db #(mshr_memory_store)::get(this, "", "memory", memory) || memory == null) begin
        `fatal("Parent environment must provide memory configuration and C++ memory store", "MSHR_MEM_CONFIG")
    end
    check_configuration();
endfunction

// 检查响应延迟、队列容量和控制开关；配置运行中改变时也会再次检查。
function void mshr_memory_driver::check_configuration();
    // 【防御性检查】以下整段校验内存代理配置，避免零拍响应、非法容量或未知开关。
    if ($isunknown(cfg.mem_read_latency_cycles) || cfg.mem_read_latency_cycles == 0) begin
        `fatal("mem_read_latency_cycles must be at least one cycle", "MSHR_MEM_CONFIG")
    end
    if ($isunknown(cfg.mem_max_pending) || cfg.mem_max_pending == 0 ||
        cfg.mem_max_pending > MSHR_ENTRIES) begin
        `fatal("Memory pending capacity must be within 1..MSHR_ENTRIES", "MSHR_MEM_CONFIG")
    end
    if ($isunknown({cfg.mem_request_enable, cfg.mem_response_enable})) begin
        `fatal("Memory enable configuration contains X/Z", "MSHR_MEM_CONFIG")
    end
endfunction

// 接收 monitor 的沿前快照；同拍先移除已握手的旧响应，再登记新请求。
// 本方法由 monitor_port 的 analysis 连接调用，不需要 sequence 手动调用 write()。
function void mshr_memory_driver::write(mshr_sample sample);
    if (!prepare_sample(sample)) begin
        return;
    end
    process_response(sample);
    process_request(sample);
endfunction

// 复位时清理空闲调度状态；正常工作每个采样沿只增加一次周期计数，并检查握手控制。
function bit mshr_memory_driver::prepare_sample(mshr_sample sample);
    // 【防御性检查】确认调用方提供有效对象，避免空句柄被继续访问。
    if (sample == null) begin
        `fatal("Memory driver received a null monitor sample", "MSHR_MEM_PROTOCOL")
    end
    if ($isunknown(sample.rst_n)) begin
        `fatal("Memory monitor reset contains X/Z", "MSHR_MEM_PROTOCOL")
    end
    if (!sample.rst_n) begin
        reset_bookkeeping();
        return 0;
    end
    check_configuration();
    cycle++;
    if ($isunknown({sample.memReadReq_valid, sample.memReadReq_ready,
        sample.memReadResp_valid, sample.memReadResp_ready})) begin
        `fatal("Memory read channel control contains X/Z", "MSHR_MEM_PROTOCOL")
    end
    return 1;
endfunction

// 允许启动或空闲再次复位；有在途读时不能擅自丢弃响应，热复位取消契约需另行明确。
// 外部 C++ 内存内容和累计请求/响应计数保留，只有下一轮调度的周期起点重新归零。
function void mshr_memory_driver::reset_bookkeeping();
    if (!is_idle()) begin
        `fatal("Reset with pending memory reads requires a defined cancellation contract", "MSHR_MEM_RESET")
    end
    pending.delete();
    outstanding.delete();
    active_response = null;
    cycle = 0;
endfunction

// 核对当前已呈现响应的ID、整行快照和最早响应拍；只有实际握手才从FIFO删除。
function void mshr_memory_driver::process_response(mshr_sample sample);
    mshr_pending_read response;
    int unsigned id;

    // 先检查已呈现响应是否被非法撤回，以及其ID/数据/到期拍是否正确。
    if (!sample.memReadResp_valid) begin
        if (active_response != null) begin
            `fatal("Presented read response was withdrawn before its handshake", "MSHR_MEM_PROTOCOL")
        end
        return;
    end
    if ($isunknown({sample.memReadResp_payload_id, sample.memReadResp_payload_rData}) ||
        active_response == null || pending.size() == 0) begin
        `fatal("Read response has unknown payload or no pending request", "MSHR_MEM_PROTOCOL")
    end
    id = sample.memReadResp_payload_id;
    if (id != active_response.id || pending[0] != active_response || !outstanding.exists(id) ||
        sample.memReadResp_payload_rData !== active_response.data ||
        cycle < active_response.due_cycle || cycle <= active_response.accepted_cycle) begin
        `fatal("Read response ID/data or response cycle does not match its request snapshot", "MSHR_MEM_PROTOCOL")
    end

    // 未握手只保持记录；握手后才从队列删除并更新响应计数。
    if (!sample.memReadResp_ready) begin
        return;
    end
    response = pending.pop_front();
    outstanding.delete(id);
    active_response = null;
    response_count++;
    `info_high($sformatf("id=%0d addr=0x%h accepted_cycle=%0d response_cycle=%0d latency_cycles=%0d configured_cycles=%0d",
        id, response.addr, response.accepted_cycle, cycle, cycle - response.accepted_cycle,
        response.due_cycle - response.accepted_cycle), "MSHR_MEM_RESPONSE_TIMING")
endfunction

// 在读请求真正握手时检查ID和容量，并从 C++ 外部内存取一次整行快照。
// 请求在第k拍接受，最早响应拍登记为k+L；FIFO排队或响应背压可延后，不能提前。
function void mshr_memory_driver::process_request(mshr_sample sample);
    mshr_pending_read response;
    int unsigned id;

    // 有效请求先检查地址与完整ID；背压期间不登记接受事件。
    if (!sample.memReadReq_valid) begin
        return;
    end
    if ($isunknown({sample.memReadReq_payload_addr, sample.memReadReq_payload_id}) ||
        sample.memReadReq_payload_addr % BLOCK_SIZE != 0 ||
        $unsigned(sample.memReadReq_payload_id) >= MSHR_ENTRIES) begin
        `fatal("Memory read request address/ID is unknown, misaligned or outside the Entry range", "MSHR_MEM_PROTOCOL")
    end
    if (!sample.memReadReq_ready) begin
        return;
    end

    // 握手后检查在途唯一与队列容量，创建固定到期拍的响应记录。
    id = sample.memReadReq_payload_id;
    if (outstanding.exists(id) || pending.size() >= cfg.mem_max_pending) begin
        `fatal("Duplicate read ID or memory pending queue overflow", "MSHR_MEM_PROTOCOL")
    end
    response = mshr_pending_read::type_id::create("response");
    response.id = id;
    response.addr = sample.memReadReq_payload_addr;
    response.accepted_cycle = cycle;
    response.due_cycle = cycle + cfg.mem_read_latency_cycles;
    // read_line() 是 model/mshr_memory_store.sv 的 SV 方法，内部调用 mshr_mem_read_line DPI，
    // 从 RefModel/MEM/SparseMemory.hpp 读取本请求的原始行；之后只使用保存的快照。
    memory.read_line(response.addr, response.data);

    // 保存请求时的内存快照并登记在途ID，后续返回不重新读取内存。
    pending.push_back(response);
    outstanding[id] = 1;
    request_count++;
endfunction

task mshr_memory_driver::run_phase(uvm_phase phase);
    drive_idle();
    forever begin
        @(negedge vif.clk or negedge vif.rst_n);
        if (vif.rst_n !== 1'b1) begin
            reset_bookkeeping();
            drive_idle();
        end else begin
            drive_memory_outputs();
        end
    end
endtask

// 复位期间关闭请求ready和响应valid，并清零当前无效的响应载荷。
task mshr_memory_driver::drive_idle();
    vif.memReadReq_ready <= 0;
    vif.memReadResp_valid <= 0;
    vif.memReadResp_payload_id <= '0;
    vif.memReadResp_payload_rData <= '0;
endtask

// 在下降沿分别准备请求接收控制和响应，供下一上升沿使用。
task mshr_memory_driver::drive_memory_outputs();
    check_configuration();
    drive_request_ready();
    drive_response();
endtask

// 接收开关有效且待响应队列有空位时拉高ready；满队列不继续接受新请求。
task mshr_memory_driver::drive_request_ready();
    vif.memReadReq_ready <= cfg.mem_request_enable && pending.size() < cfg.mem_max_pending;
endtask

// 队首到期后才呈现响应；已经呈现的对象锁定到握手，不受后续响应开关变化影响。
// cycle是刚采样结束的上升沿，使用cycle+1判断下一沿到期，保证L拍延迟没有多等一拍。
task mshr_memory_driver::drive_response();
    if (active_response == null && cfg.mem_response_enable && pending.size() > 0) begin
        if (cycle + 1 >= pending[0].due_cycle) begin
            active_response = pending[0];
        end
    end

    // 把锁定记录驱动到下一采样沿；没有响应时才撤销valid。
    if (active_response != null) begin
        vif.memReadResp_valid <= 1;
        vif.memReadResp_payload_id <= BUS_ID_WIDTH'(active_response.id);
        vif.memReadResp_payload_rData <= active_response.data;
    end else begin
        vif.memReadResp_valid <= 0;
        vif.memReadResp_payload_id <= '0;
        vif.memReadResp_payload_rData <= '0;
    end
endtask

// 检查待响应FIFO、在途ID及已呈现对象全部为空，供环境等待读内存侧排空。
function bit mshr_memory_driver::is_idle();
    return pending.size() == 0 && outstanding.num() == 0 && active_response == null;
endfunction

function void mshr_memory_driver::check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!is_idle() || request_count != response_count) begin
        `error($sformatf("Memory reads did not drain: requests=%0d responses=%0d pending=%0d",
            request_count, response_count, pending.size()), "MSHR_MEM_DRAIN")
    end
endfunction
