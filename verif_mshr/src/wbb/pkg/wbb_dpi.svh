// 以下为 C++ DPI 导入接口，实现在 verif_mshr/dpi/wbb_dpi.cpp。
// wbb_ref_* 调用 RefModel/Cache/WriteBackBuffer.hpp 中的已有 WBB 模型。
// sparse_mem_* 调用 RefModel/MEM/SparseMemory.hpp 中的稀疏内存模型。
// int 返回值统一为 1=成功、0=失败，失败后读取 wbb_dpi_last_error() 并报告错误。
// 仅在调用成功后使用 output 参数；handle 是 C++ 实例的 chandle，复位后可继续使用，销毁后失效。
// 整行 line 的最低 32 位对应 C++ Line[0]，以此类推；所有存储操作均不等待 SV 时钟。
// 本文件只有 import 声明，下面的说明用于查阅调用约定，具体处理流程见对应 C++ 函数实现。

// 读取最近一次 DPI 失败原因；在返回 0 后立即调用，避免后续调用清空或覆盖错误。
import "DPI-C" function string wbb_dpi_last_error();

// 创建 C++ WBB 模型并核对六项配置，通过 handle 返回实例句柄。
import "DPI-C" function int wbb_ref_create(input int aw, dw, block_size, entries,
    slotw, busw, output chandle handle);

// 复位指定 C++ WBB 实例，句柄继续有效。
import "DPI-C" function int wbb_ref_reset(input chandle handle);

// 销毁指定 C++ WBB 实例，成功后调用方将 handle 置 null。
import "DPI-C" function int wbb_ref_destroy(input chandle handle);

// 读取排空状态到 empty（1 为空，0 为非空）；函数返回值仍是调用成功/失败。
import "DPI-C" function int wbb_ref_empty(input chandle handle, output int empty);

// 输入当前拍采样，返回 tick() 前的组合预测，再调用一次 C++ tick() 更新状态。
// resp_valid 传入响应握手结果；输出发送载荷仅在 send_valid=1 时有效。
import "DPI-C" function int wbb_ref_step(input chandle handle,
    input int reserve_en, input int unsigned reserve_addr,
    input int push_en, input int unsigned push_slot,
    input bit [LINE_WIDTH-1:0] push_line, input int send_ready, resp_valid,
    input int unsigned resp_id, q0, q1,
    output int reserve_ok, reserve_slot, full, q0_same, q1_same, send_valid,
    output int unsigned send_addr, output bit [LINE_WIDTH-1:0] send_data,
    output int unsigned send_id);

// 创建一份独立的稀疏内存并校验配置，page_size 单位为字节，handle 标识该实例。
import "DPI-C" function int sparse_mem_create(input int page_size, aw, dw, block_size,
    output chandle handle);

// 清空指定稀疏内存的全部页面，恢复为逻辑全零内存，句柄保持有效。
import "DPI-C" function int sparse_mem_reset(input chandle handle);

// 销毁指定稀疏内存及其页面，成功后调用方将 handle 置 null。
import "DPI-C" function int sparse_mem_destroy(input chandle handle);

// 将 line 整行写到指定实例的块地址 addr；存储立即更新，响应时间由 SV 管理。
import "DPI-C" function int sparse_mem_write_line(input chandle handle,
    input int unsigned addr, input bit [LINE_WIDTH-1:0] line);

// 从指定实例回读整行到 line，供实际/期望内存比较；未写区域返回零。
import "DPI-C" function int sparse_mem_read_line(input chandle handle,
    input int unsigned addr, output bit [LINE_WIDTH-1:0] line);
