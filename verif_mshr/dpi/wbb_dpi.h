#pragma once
#include <cstdint>

// Packed SV bit vectors use 32-bit words, least significant word first.
// No exceptions may cross this C ABI: 1 = success, 0 = failure; inspect last_error.
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
