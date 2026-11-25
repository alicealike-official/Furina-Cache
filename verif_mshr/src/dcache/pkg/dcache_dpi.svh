// 实现位于dpi/dcache_dpi.cpp；对象分别为原CacheTop和原SparseMemory。
// 创建/销毁独立实例，避免不同case或不同用途共用状态。
import "DPI-C" function chandle dcache_ref_create();
import "DPI-C" function void dcache_ref_destroy(chandle handle);
// 给原CacheTop设置沿前输入，eval取得输出，再tick恰好一次；复位时调用原reset。
import "DPI-C" function int dcache_ref_step(chandle handle, bit reset_active,
    input int unsigned inputs[], output int unsigned outputs[]);
// 创建/销毁后端存储；读写整行不会自行产生总线控制信号。
import "DPI-C" function chandle dcache_mem_create();
import "DPI-C" function void dcache_mem_destroy(chandle handle);
import "DPI-C" function int dcache_mem_read(chandle handle, int unsigned addr, output bit [511:0] data);
import "DPI-C" function int dcache_mem_write(chandle handle, int unsigned addr, input bit [511:0] data);
// 返回最近一次DPI调用失败的原因。
import "DPI-C" function string dcache_last_error();

// 独立FIFO策略实例；复用原FifoPolicy，仅提供受保护顺序的只读导出。
import "DPI-C" function chandle dcache_fifo_create();
import "DPI-C" function void dcache_fifo_destroy(chandle handle);
import "DPI-C" function int dcache_fifo_step(chandle handle, bit reset_active,
    bit hit, int hit_set, int hit_way, bit fill, int fill_set, int fill_way,
    int query_set, int valid_mask, int lock_mask, output int candidate,
    output bit [255:0] order);

// 原CacheMem独立实例；按实际端口推进，碰撞返回值由checker按未定原语范围排除。
import "DPI-C" function chandle dcache_memref_create();
import "DPI-C" function void dcache_memref_destroy(chandle handle);
import "DPI-C" function int dcache_memref_step(chandle handle, bit reset_active,
    input int unsigned inputs[], output int unsigned outputs[]);
