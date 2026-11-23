// sparse_mem_* / wbb_dpi_last_error 为 DPI 函数，声明由 pkg/wbb_dpi.svh 导入 wbb_pkg。
// 适配实现见 verif_mshr/dpi/wbb_dpi.cpp，实际存储模型见 RefModel/MEM/SparseMemory.hpp。
// 失败分支通过 wbb_dpi_last_error() 立即读取 C++ 返回的错误原因。
class wbb_memory_store extends uvm_object;
    // C++ SparseMemory 实际内存句柄，保存 DUT 写请求数据；模型定义见 RefModel/MEM/SparseMemory.hpp。
    protected chandle actual_handle;
    // 独立的 C++ SparseMemory 期望内存句柄，保存 WBB 参考模型预测的写数据。
    protected chandle expected_handle;
    protected bit touched[int unsigned];

    `uvm_object_utils(wbb_memory_store)

    function new(string name = "wbb_memory_store");
        super.new(name);
    endfunction

    extern function void initialize(int page_size);
    extern function void write_actual(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    extern function void write_expected(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    extern function void read_actual(int unsigned addr, output bit [LINE_WIDTH-1:0] data);
    extern function void compare_contents();
    extern function void close();

endclass

// 创建实际和期望两份 C++ 稀疏内存，并保存各自句柄供后续读写。
function void wbb_memory_store::initialize(int page_size);
    // 【防御性检查】检查C++内存封装的初始化顺序，避免未创建就使用或重复创建。
    if (actual_handle != null || expected_handle != null) begin
        `fatal("Memory store already initialized")
    end
    // DPI 调用：创建实际 SparseMemory，后续存储 DUT 已握手的写数据。
    if (!sparse_mem_create(page_size, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, actual_handle)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
    // DPI 调用：另建独立的期望 SparseMemory，存储 WBB 参考模型预测的数据。
    if (!sparse_mem_create(page_size, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, expected_handle)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
endfunction

// 将 DUT 已握手的写事务落到实际 C++ 内存，并登记需要在收尾比较的地址。
function void wbb_memory_store::write_actual(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    // DPI 调用：sparse_mem_write_line 最终执行实际实例的 SparseMemory::writeLine(addr, line)。
    if (!sparse_mem_write_line(actual_handle, addr, data)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
    touched[addr] = 1;
endfunction

// 将 WBB 模型预测的写事务落到期望 C++ 内存，并登记比较地址。
function void wbb_memory_store::write_expected(int unsigned addr, bit [LINE_WIDTH-1:0] data);
    // DPI 调用：使用期望实例的句柄执行 SparseMemory::writeLine(addr, line)。
    if (!sparse_mem_write_line(expected_handle, addr, data)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
    touched[addr] = 1;
endfunction

// 回读实际 C++ 稀疏内存中的整行，供定向 case 与原始激励比较；不分配页面或改写期望内存。
function void wbb_memory_store::read_actual(int unsigned addr, output bit [LINE_WIDTH-1:0] data);
    // DPI 调用：实际实例的 SparseMemory::readLine(addr)，声明见 pkg/wbb_dpi.svh。
    if (!sparse_mem_read_line(actual_handle, addr, data)) begin
        `fatal(wbb_dpi_last_error(), "MEM_DPI")
    end
endfunction

// 经 DPI 回读实际/期望内存中所有受测地址的整行数据，并在 SV 中比较。
function void wbb_memory_store::compare_contents();
    bit [LINE_WIDTH-1:0] actual;
    bit [LINE_WIDTH-1:0] expected;
    // Union of both write-address sets catches missing and stray writes.
    foreach (touched[addr]) begin
        // 两次 DPI 调用分别执行实际/期望实例的 SparseMemory::readLine(addr)。
        // 返回数据写入 actual/expected，DPI 声明见 pkg/wbb_dpi.svh。
        if (!sparse_mem_read_line(actual_handle, addr, actual) ||
            !sparse_mem_read_line(expected_handle, addr, expected)) begin
            `fatal(wbb_dpi_last_error(), "MEM_DPI")
        end
        if (actual !== expected) begin
            `error($sformatf("Backing memory mismatch at 0x%h: expected=%h actual=%h",
                addr, expected, actual), "MEM_COMPARE")
        end
    end
endfunction

// 经 DPI 销毁两份 C++ 稀疏内存及其页面，随后清空本对象持有的句柄。
function void wbb_memory_store::close();
    if (actual_handle != null) begin
        // DPI 调用：释放 actual_handle 对应的 C++ SparseMemory。
        if (!sparse_mem_destroy(actual_handle)) begin
            `error(wbb_dpi_last_error(), "MEM_DPI")
        end
        actual_handle = null;
    end
    if (expected_handle != null) begin
        // DPI 调用：释放 expected_handle 对应的 C++ SparseMemory。
        if (!sparse_mem_destroy(expected_handle)) begin
            `error(wbb_dpi_last_error(), "MEM_DPI")
        end
        expected_handle = null;
    end
endfunction
