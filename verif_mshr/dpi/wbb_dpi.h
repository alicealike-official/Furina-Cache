#pragma once
#include <cstdint>

// SV 导入声明位于 src/wbb/pkg/wbb_dpi.svh，各函数用途在 wbb_dpi.cpp 的实现前说明。
// packed 行按低位 32-bit 字在前传递。int 返回 1 表示成功，0 表示失败。
// 失败后立即读取 wbb_dpi_last_error()，只在成功时使用输出参数；异常由适配层转换为失败状态。
extern "C" {
const char* wbb_dpi_last_error();
int wbb_ref_create(int aw, int dw, int block, int entries, int slotw, int busw, void** handle);
int wbb_ref_reset(void* handle);
int wbb_ref_destroy(void* handle);
int wbb_ref_empty(void* handle, int* empty);
int wbb_ref_step(void* handle,
    int reserve_en, uint32_t reserve_addr, int push_en, uint32_t push_slot,
    const uint32_t* push_line, int send_ready, int resp_valid, uint32_t resp_id,
    uint32_t q0, uint32_t q1, int* reserve_ok, int* reserve_slot, int* full,
    int* q0_same, int* q1_same, int* send_valid, uint32_t* send_addr,
    uint32_t* send_data, uint32_t* send_id);
int sparse_mem_create(int page_size, int aw, int dw, int block, void** handle);
int sparse_mem_reset(void* handle);
int sparse_mem_destroy(void* handle);
int sparse_mem_write_line(void* handle, uint32_t addr, const uint32_t* line);
int sparse_mem_read_line(void* handle, uint32_t addr, uint32_t* line);
}
