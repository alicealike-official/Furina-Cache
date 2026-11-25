// 原C++ SparseMemory的SV封装；所有dcache_mem_*声明由pkg/dcache_dpi.svh导入。
class dcache_memory_store extends uvm_object;
    protected chandle handle;
    `uvm_object_utils(dcache_memory_store)
    function new(string name = "dcache_memory_store");
        super.new(name);
    endfunction
    // 经DPI创建独立后端存储，未写过的字节由原模型返回0。
    function void initialize();
        handle = dcache_mem_create();
        if (handle == null) begin
            `fatal(dcache_last_error(), "DCACHE_MEMORY")
        end
    endfunction
    // 读取请求接受时的整行快照，不访问DUT内部。
    function void read_line(bit [31:0] addr, output bit [511:0] data);
        if (!dcache_mem_read(handle, addr, data)) begin
            `fatal(dcache_last_error(), "DCACHE_MEMORY")
        end
    endfunction
    // 写请求实际握手时更新原C++稀疏内存，CPU写不会直接调用此方法。
    function void write_line(bit [31:0] addr, bit [511:0] data);
        if (!dcache_mem_write(handle, addr, data)) begin
            `fatal(dcache_last_error(), "DCACHE_MEMORY")
        end
    endfunction
    // 环境结束时释放DPI创建的存储对象。
    function void close();
        dcache_mem_destroy(handle);
        handle = null;
    endfunction
endclass
