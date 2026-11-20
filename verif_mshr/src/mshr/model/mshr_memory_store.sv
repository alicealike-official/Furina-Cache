// mshr_mem_* 为 pkg/mshr_dpi.svh 声明的 DPI 函数，适配实现在 dpi/mshr_dpi.cpp。
// 本类只封装已有 RefModel/MEM/SparseMemory.hpp，不负责内存通道的握手或响应调度。
class mshr_memory_store extends uvm_object;
    // C++ SparseMemory 实例句柄，保存外部内存中的原始行；MSHR fill 不回写这个存储。
    protected chandle memory_handle;

    `uvm_object_utils(mshr_memory_store)

    function new(string name = "mshr_memory_store");
        super.new(name);
    endfunction

    extern function void initialize(int page_size);
    extern function void require_initialized();
    extern function void write_line(bit [ADDR_WIDTH-1:0] addr, bit [LINE_WIDTH-1:0] data);
    extern function void read_line(bit [ADDR_WIDTH-1:0] addr, output bit [LINE_WIDTH-1:0] data);
    extern function void close();

endclass

// 创建外部内存的 C++ 实例并核对 SV/C++ 配置；重复初始化会明确报错。
function void mshr_memory_store::initialize(int page_size);
    if (memory_handle != null) begin
        `fatal("MSHR memory store is already initialized", "MSHR_MEM_DPI")
    end
    // DPI 调用：mshr_mem_create 最终创建 SparseMemory，句柄保存到 memory_handle。
    if (!mshr_mem_create(page_size, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, memory_handle)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_MEM_DPI")
    end
endfunction

// 在读写前确认 C++ 实例已经创建，避免把空句柄传给 DPI 后才暴露调用顺序问题。
function void mshr_memory_store::require_initialized();
    if (memory_handle == null) begin
        `fatal("MSHR memory store must be initialized before use", "MSHR_MEM_DPI")
    end
endfunction

// 通过 C++ 稀疏内存预置一个块的数据；该方法不对 DUT 做后门访问。
function void mshr_memory_store::write_line(bit [ADDR_WIDTH-1:0] addr, bit [LINE_WIDTH-1:0] data);
    require_initialized();
    // DPI 调用：mshr_mem_write_line 执行 SparseMemory::writeLine(addr, line)。
    if (!mshr_mem_write_line(memory_handle, addr, data)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_MEM_DPI")
    end
endfunction

// 读取 C++ 外部内存中的整行；memory driver 在读请求握手时调用它，固定本次响应快照。
function void mshr_memory_store::read_line(bit [ADDR_WIDTH-1:0] addr, output bit [LINE_WIDTH-1:0] data);
    require_initialized();
    // DPI 调用：mshr_mem_read_line 执行 SparseMemory::readLine(addr)，不会推进 MSHR 模型。
    if (!mshr_mem_read_line(memory_handle, addr, data)) begin
        `fatal(mshr_dpi_last_error(), "MSHR_MEM_DPI")
    end
endfunction

// 销毁 C++ 稀疏内存实例；仅在环境收尾调用，DUT 的空闲复位不会清空外部内存内容。
function void mshr_memory_store::close();
    if (memory_handle != null) begin
        // DPI 调用：mshr_mem_destroy 释放该 SparseMemory 实例及其页面。
        if (!mshr_mem_destroy(memory_handle)) begin
            `error(mshr_dpi_last_error(), "MSHR_MEM_DPI")
        end
        memory_handle = null;
    end
endfunction
