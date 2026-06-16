#include "sparse_memory.h"
#include <cassert>
#include <cmath>


Sparse_Memory::Sparse_Memory(
    sc_core::sc_module_name name,
    uint64_t page_size,
    double latency
) : sc_core::sc_module(name),
    mem_receive_socket("mem_receive_socket"),
    // mem_resp_socket("mem_resp_socket"),
    page_size_(page_size),
    latency_(latency)
{
    mem_receive_socket.register_b_transport(this, &Sparse_Memory::b_transport);
    assert((page_size & (page_size-1)) == 0);
    page_mask_ = page_size-1;
    page_offset_bits_ = static_cast<unsigned int> (std::log2(page_size));
}

Sparse_Memory::~Sparse_Memory() {
    for (auto& pair : page_table_) {
        delete pair.second;
    }
}

void Sparse_Memory::b_transport(
    tlm::tlm_generic_payload& trans,
    sc_core::sc_time& delay
) {
    tlm::tlm_command cmd = trans.get_command();
    uint64_t addr = trans.get_address();
    uint8_t* data_ptr = trans.get_data_ptr();
    unsigned data_len = trans.get_data_length();

    uint64_t page_start = page_align(addr);
    uint64_t page_end = page_align(addr + data_len - 1);

    // 如果不在同一页，分两页传输
    if (page_start != page_end) {
        uint64_t first_chunk = page_size_ - (addr & page_mask_);

        // 第一部分
        tlm::tlm_generic_payload first_trans;
        first_trans.set_command(cmd);
        first_trans.set_address(addr);
        first_trans.set_data_ptr(data_ptr);
        first_trans.set_data_length(first_chunk);
        b_transport(first_trans, delay);

        // 第二部分
        tlm::tlm_generic_payload second_trans;
        second_trans.set_command(cmd);
        second_trans.set_address(addr + first_chunk);
        second_trans.set_data_ptr(data_ptr + first_chunk);
        second_trans.set_data_length(data_len - first_chunk);
        b_transport(second_trans, delay);
        
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
        return;
    }

    // 如果在同一页
    Page* page = get_page(addr, (cmd == tlm::TLM_WRITE_COMMAND));

    if (page == nullptr) {
        trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return;
    }

    unsigned offset = addr & page_mask_;
    if (cmd == tlm::TLM_READ_COMMAND) {
        std::memcpy(data_ptr, page->data+offset, data_len);
    }
    else if (cmd == tlm::TLM_WRITE_COMMAND) {
        std::memcpy(page->data+offset, data_ptr, data_len);
    }
    // 未知命令
    else {
        trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return;
    }

    delay+=sc_core::sc_time(latency_, sc_core::SC_NS);

    trans.set_response_status(tlm::TLM_OK_RESPONSE);
}

Sparse_Memory::Page* Sparse_Memory::get_page(
    uint64_t addr,
    bool allocate
) {
    uint64_t page_base = page_align(addr);

    // 查找对应key，如果没找到，it会指向page_table_.end()
    // 如果找到，返回it key-value中的第二个(value)
    auto it = page_table_.find(page_base);
    if (it != page_table_.end()) {
        return it -> second;
    }

    //既没找到，也没有分配
    if (!allocate) {    
        return nullptr;
    }

    //没找到，但是分配了
    //堆上分配内存，返回函数不回收
    Page* page = new Page(page_base, page_size_);
    page_table_[page_base] = page;
    return page;
}

uint64_t Sparse_Memory::page_align(uint64_t addr) const {
    return addr & ~page_mask_;
}

