// 这里导入的是C++ DPI函数，函数体位于 verif_mshr/dpi/mshr_dpi.cpp。
// mshr_ref_* 调用 RefModel/Cache/MSHR.hpp；mshr_mem_* 调用 RefModel/MEM/SparseMemory.hpp。
// 返回1表示成功，0表示失败；失败后立即读取mshr_dpi_last_error，不能继续使用输出。
// chandle标识C++实例；整行最低DATA_WIDTH位对应C++ Line[0]，当前适配要求32位字。

// 取得最近一次失败原因，后续成功调用会清空它。
import "DPI-C" function string mshr_dpi_last_error();

// 核对SV/C++容量、地址和索引位宽，并创建原有C++ MSHR实例。
import "DPI-C" function int mshr_ref_create(input int aw, dw, block_size,
    entries, pending, sets, ways, tagw, indexw, wayw, wordoffw,
    entryw, slotw, cpuw, busw, wbb_entries, wbb_slotw, output chandle handle);

// 清空指定C++ MSHR，保留实例句柄；是否允许取消在途事务由调用方先检查。
import "DPI-C" function int mshr_ref_reset(input chandle handle);

// 销毁C++ MSHR实例；成功后调用方将句柄清成null。
import "DPI-C" function int mshr_ref_destroy(input chandle handle);

// 查询模型是否全部排空，empty=1表示空；函数返回值表示查询调用本身是否成功。
import "DPI-C" function int mshr_ref_empty(input chandle handle, output int empty);

// 设置本拍输入、读取全部沿前预测，再调用一次tick；每个采样沿只调用一次。
// resp_fire必须传入valid&&ready；sendReq/fillReq有呈现副作用，统一在本函数内调用。
// 无效查询索引可能为-1，SV只能在对应hit/slotFree/hasFree有效时比较。
import "DPI-C" function int mshr_ref_step(input chandle handle,
    input int alloc_en,
    input int unsigned alloc_tag,
    input int unsigned alloc_index,
    input int unsigned alloc_way,
    input int alloc_is_write,
    input int unsigned alloc_wdata,
    input int unsigned alloc_word_off,
    input int unsigned alloc_resp_id,
    input int alloc_has_wb,
    input int unsigned alloc_wb_slot,
    input int merge_en,
    input int unsigned merge_entry,
    input int merge_is_write,
    input int unsigned merge_wdata,
    input int unsigned merge_word_off,
    input int unsigned merge_resp_id,
    input int unsigned q0_tag,
    input int unsigned q0_index,
    input int unsigned q1_tag,
    input int unsigned q1_index,
    input int send_ready,
    input int resp_fire,
    input int unsigned resp_id,
    input bit [LINE_WIDTH-1:0] resp_line,
    input int fill_ready,
    input int replay_ready,
    output int hasFree,
    output int freeEntry,
    output int m0_hit,
    output int m0_entry,
    output int m0_mergeable,
    output int m0_slotFree,
    output int m0_freeSlot,
    output int m1_hit,
    output int m1_entry,
    output int m1_mergeable,
    output int m1_slotFree,
    output int m1_freeSlot,
    output int memReadReq_valid,
    output int unsigned memReadReq_payload_addr,
    output int unsigned memReadReq_payload_id,
    output int fill_en,
    output int unsigned fill_tag,
    output int unsigned fill_index,
    output int unsigned fill_way,
    output int fill_dirty,
    output bit [LINE_WIDTH-1:0] fill_line,
    output int replay_valid,
    output int replay_payload_isWrite,
    output int unsigned replay_payload_id,
    output int unsigned replay_payload_rData);

// 创建独立C++稀疏内存，page_size单位为字节；内存只存数据，不控制总线时序。
import "DPI-C" function int mshr_mem_create(input int page_size, aw, dw, block_size,
    output chandle handle);

// 清空稀疏内存所有页面；MSHR复位通常不清后端内存，调用方按场景决定。
import "DPI-C" function int mshr_mem_reset(input chandle handle);

// 销毁指定C++稀疏内存实例。
import "DPI-C" function int mshr_mem_destroy(input chandle handle);

// 在块对齐地址预置外部内存整行；不是对DUT内部状态的后门写。
import "DPI-C" function int mshr_mem_write_line(input chandle handle,
    input int unsigned addr, input bit [LINE_WIDTH-1:0] line);

// 读取块对齐地址的原始整行；memory driver在请求握手时调用并保存响应快照。
import "DPI-C" function int mshr_mem_read_line(input chandle handle,
    input int unsigned addr, output bit [LINE_WIDTH-1:0] line);
