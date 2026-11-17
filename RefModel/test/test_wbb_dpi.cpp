// Adapter contract checks, not additional DUT functional cases.
#include "../../verif_mshr/dpi/wbb_dpi.h"
#include "params.hpp"
#include <cassert>
#include <cstring>
#include <iostream>
using namespace dcache;

int main() {
    void* ref = nullptr;
    assert(!wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, 2, 1, BUS_ID_WIDTH, &ref));
    assert(ref == nullptr && std::strlen(wbb_dpi_last_error()) > 0);
    assert(!wbb_ref_create(64, DATA_WIDTH, BLOCK_SIZE, WBB_ENTRIES, WBB_ID_WIDTH, BUS_ID_WIDTH, &ref));
    assert(wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, WBB_ENTRIES, WBB_ID_WIDTH, BUS_ID_WIDTH, &ref));
    int ok, slot, full, q0, q1, valid, empty;
    uint32_t addr, id;
    Line input{}, output{};
    for (int w = 0; w < WORDS_PER_BLOCK; ++w) input[w] = 0x01020304u + w;
    auto step = [&](int reserve, int push, int ready, int response) {
        return wbb_ref_step(ref, reserve, 0x1000, push, 0, input.data(), ready,
            response, 0, 0x1000, 0x2000, &ok, &slot, &full, &q0, &q1, &valid,
            &addr, output.data(), &id);
    };
    assert(!step(0, 1, 0, 0)); // illegal push rejected before tick
    assert(step(1, 0, 0, 0));
    assert(ok == 1 && slot == 0 && q0 == 0 && valid == 0); // pre-edge view
    assert(step(0, 1, 0, 0));
    assert(q0 == 1 && q1 == 0 && valid == 0);
    assert(step(0, 0, 1, 0));
    assert(valid == 1 && id == 0 && addr == 0x1000 && output == input);
    assert(wbb_ref_empty(ref, &empty) && !empty);
    assert(step(0, 0, 0, 1));
    assert(valid == 0 && q0 == 1);
    assert(wbb_ref_empty(ref, &empty) && empty);
    assert(wbb_ref_reset(ref));
    assert(wbb_ref_destroy(ref));
    assert(!wbb_ref_reset(ref));
    assert(!wbb_ref_destroy(nullptr));

    void* actual = nullptr;
    void* expected = nullptr;
    assert(!sparse_mem_create(3, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, &actual));
    assert(!sparse_mem_create(4096, ADDR_WIDTH, 64, BLOCK_SIZE, &actual));
    assert(sparse_mem_create(16, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, &actual));
    assert(sparse_mem_create(4096, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, &expected));
    assert(sparse_mem_write_line(actual, 0x1000, input.data()));
    assert(sparse_mem_read_line(actual, 0x1000, output.data()) && output == input);
    assert(sparse_mem_read_line(expected, 0x1000, output.data()) && output == Line{});
    assert(sparse_mem_write_line(expected, 0x1000, input.data()));
    assert(sparse_mem_read_line(expected, 0x1000, output.data()) && output == input);
    assert(!sparse_mem_write_line(actual, 3, input.data()));
    assert(sparse_mem_reset(actual));
    assert(sparse_mem_read_line(actual, 0x1000, output.data()) && output == Line{});
    assert(sparse_mem_destroy(actual) && sparse_mem_destroy(expected));
    std::cout << "WBB / sparse-memory DPI adapter checks passed\n";
}
