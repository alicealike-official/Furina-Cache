#ifndef SPARSE_MEMORY_H
#define SPARSE_MEMORY_H

#include <systemc>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>
#include <unordered_map>
#include <cstdint>
#include <cstring>
#include "utils.h"
#include <cassert>
#include <cmath>

class Sparse_Memory : public sc_core::sc_module {

public:
    tlm_utils::simple_target_socket<Sparse_Memory> mem_receive_socket;
    // tlm_utils::simple_initiator_socket<Sparse_Memory> mem_resp_socket;
    Sparse_Memory(sc_core::sc_module_name name, uint64_t page_size, double latency);
    ~Sparse_Memory();

    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);

private:
    struct Page
    {
        uint8_t* data;
        uint64_t base_addr;
        uint64_t size;

        Page(uint64_t addr, uint64_t sz) : 
            base_addr(addr),
            size(sz)
        {
            data = new uint8_t[size];
            std::memset(data, 0, size);
        }

        ~Page() {
            delete[] data;
        }

        Page(const Page&) = delete;
        Page& operator=(const Page&) = delete;
    };

    std::unordered_map<uint64_t, Page*> page_table_;
    uint64_t page_size_;
    uint64_t page_mask_;
    unsigned page_offset_bits_;
    double latency_;

    Page* get_page(uint64_t addr);
    uint64_t page_align(uint64_t addr) const;
};

#endif
