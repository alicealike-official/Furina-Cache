#pragma once
#include <cstdint>

// SV 导入声明位于 src/mshr/pkg/mshr_dpi.svh，函数用途在 mshr_dpi.cpp 的定义前说明。
// packed 行以最低32位字在前；所有int返回1表示成功、0表示失败，失败后立即读取错误文本。
// 输出参数只在调用成功后有效；句柄由本适配层管理，不能用DUT或其他模型对象的地址替代。
extern "C" {
const char* mshr_dpi_last_error();
int mshr_ref_create(int aw, int dw, int block, int entries, int pending, int sets, int ways, int tagw, int indexw, int wayw, int wordoffw, int entryw, int slotw, int cpuw, int busw, int wbb_entries, int wbb_slotw, void** handle);
int mshr_ref_reset(void* handle);
int mshr_ref_destroy(void* handle);
int mshr_ref_empty(void* handle, int* empty);
int mshr_ref_step(void* handle,
    int alloc_en,
    uint32_t alloc_tag,
    uint32_t alloc_index,
    uint32_t alloc_way,
    int alloc_is_write,
    uint32_t alloc_wdata,
    uint32_t alloc_word_off,
    uint32_t alloc_resp_id,
    int alloc_has_wb,
    uint32_t alloc_wb_slot,
    int merge_en,
    uint32_t merge_entry,
    int merge_is_write,
    uint32_t merge_wdata,
    uint32_t merge_word_off,
    uint32_t merge_resp_id,
    uint32_t q0_tag,
    uint32_t q0_index,
    uint32_t q1_tag,
    uint32_t q1_index,
    int send_ready,
    int resp_fire,
    uint32_t resp_id,
    const uint32_t* resp_line,
    int fill_ready,
    int replay_ready,
    int* hasFree,
    int* freeEntry,
    int* m0_hit,
    int* m0_entry,
    int* m0_mergeable,
    int* m0_slotFree,
    int* m0_freeSlot,
    int* m1_hit,
    int* m1_entry,
    int* m1_mergeable,
    int* m1_slotFree,
    int* m1_freeSlot,
    int* memReadReq_valid,
    uint32_t* memReadReq_payload_addr,
    uint32_t* memReadReq_payload_id,
    int* fill_en,
    uint32_t* fill_tag,
    uint32_t* fill_index,
    uint32_t* fill_way,
    int* fill_dirty,
    uint32_t* fill_line,
    int* replay_valid,
    int* replay_payload_isWrite,
    uint32_t* replay_payload_id,
    uint32_t* replay_payload_rData);
int mshr_mem_create(int page_size, int aw, int dw, int block, void** handle);
int mshr_mem_reset(void* handle);
int mshr_mem_destroy(void* handle);
int mshr_mem_write_line(void* handle, uint32_t addr, const uint32_t* line);
int mshr_mem_read_line(void* handle, uint32_t addr, uint32_t* line);
}
