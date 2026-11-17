#include "wbb_dpi.h"
#include <stdexcept>
#include <string>
#include <memory>
#include <unordered_map>
#include <algorithm>
// Keep the model's existing assertions, but translate failures to DPI status.
#define DCACHE_WBB_ASSERT(x) do { if (!(x)) throw std::runtime_error("WBB model assertion: " #x); } while (0)
#include "../../RefModel/Cache/WriteBackBuffer.hpp"
#include "../../RefModel/MEM/SparseMemory.hpp"

namespace {
thread_local std::string error;
std::unordered_map<void*, std::unique_ptr<dcache::WriteBackBuffer>> refs;
std::unordered_map<void*, std::unique_ptr<dcache::SparseMemory>> memories;

template<class F> int protect(F action) noexcept {
    try {
        action();
        error.clear();
        return 1;
    } catch (const std::exception& e) {
        error = e.what();
    } catch (...) {
        error = "Unknown C++ model failure";
    }
    return 0;
}

void require(bool condition, const char* message) {
    if (!condition) throw std::invalid_argument(message);
}

template<class T> T& lookup(std::unordered_map<void*, std::unique_ptr<T>>& objects, void* h) {
    auto it = objects.find(h);
    require(it != objects.end(), "Invalid or destroyed model handle");
    return *it->second;
}

void checkMemoryConfig(int aw, int dw, int block) {
    require(aw == dcache::ADDR_WIDTH && dw == dcache::DATA_WIDTH && block == dcache::BLOCK_SIZE,
        "SV and C++ memory parameters differ");
}
}

extern "C" const char* wbb_dpi_last_error() { return error.c_str(); }

extern "C" int wbb_ref_create(int aw, int dw, int block, int entries, int slotw, int busw, void** h) {
    return protect([&] {
        require(h != nullptr, "Null handle output");
        *h = nullptr;
        checkMemoryConfig(aw, dw, block);
        require(entries == dcache::WBB_ENTRIES && slotw == dcache::WBB_ID_WIDTH &&
            busw == dcache::BUS_ID_WIDTH, "SV and C++ WBB parameters differ");
        auto model = std::make_unique<dcache::WriteBackBuffer>();
        *h = model.get();
        refs.emplace(*h, std::move(model));
    });
}
extern "C" int wbb_ref_reset(void* h) {
    return protect([&] { lookup(refs, h).reset(); });
}
extern "C" int wbb_ref_destroy(void* h) {
    return protect([&] { require(refs.erase(h) == 1, "Invalid WBB handle"); });
}
extern "C" int wbb_ref_empty(void* h, int* empty) {
    return protect([&] {
        require(empty != nullptr, "Null empty output");
        auto& model = lookup(refs, h);
        *empty = 1;
        for (int i = 0; i < dcache::WBB_ENTRIES; ++i)
            if (model.getValid(i) || model.getReserved(i) || model.getIssued(i)) *empty = 0;
    });
}
extern "C" int wbb_ref_step(void* h,
    int reserve_en, uint32_t reserve_addr, int push_en, uint32_t push_slot,
    const uint32_t* push_line, int send_ready, int resp_valid, uint32_t resp_id,
    uint32_t q0, uint32_t q1, int* reserve_ok, int* reserve_slot, int* full,
    int* q0_same, int* q1_same, int* send_valid, uint32_t* send_addr,
    uint32_t* send_data, uint32_t* send_id) {
    return protect([&] {
        require(push_line && reserve_ok && reserve_slot && full && q0_same && q1_same &&
            send_valid && send_addr && send_data && send_id, "Null step argument");
        auto& model = lookup(refs, h);
        if (push_en) {
            require(push_slot < dcache::WBB_ENTRIES, "Push slot out of range");
            require(model.getReserved(push_slot), "Push requires an existing reservation");
        }
        if (resp_valid) {
            require(resp_id < dcache::WBB_ENTRIES, "Response ID out of range");
            require(model.getIssued(resp_id), "Response requires an issued request");
        }
        if (reserve_en) {
            require(reserve_addr == dcache::toBlockAddr(reserve_addr), "Reserve address misaligned");
            require(!model.reserveOk() || !model.hasSameAddr(reserve_addr), "Duplicate reserved address");
        }
        model.rsv_req = {reserve_en != 0, reserve_addr};
        model.push_req = {};
        model.push_req.en = push_en != 0;
        model.push_req.slot = static_cast<int>(push_slot);
        std::copy_n(push_line, dcache::WORDS_PER_BLOCK, model.push_req.line.begin());
        model.mem_wr_ready = send_ready != 0;
        model.mem_wr_resp = {resp_valid != 0, resp_id};
        // All predictions belong to the pre-edge state.
        auto reserve = model.reserve();
        auto send = model.sendReq();
        *reserve_ok = reserve.ok;
        *reserve_slot = reserve.slot;
        *full = model.full();
        *q0_same = model.hasSameAddr(q0);
        *q1_same = model.hasSameAddr(q1);
        *send_valid = send.en;
        *send_addr = send.addr;
        *send_id = send.id;
        std::copy(send.data.begin(), send.data.end(), send_data);
        model.tick();
    });
}
extern "C" int sparse_mem_create(int page, int aw, int dw, int block, void** h) {
    return protect([&] {
        require(h != nullptr, "Null memory handle output");
        *h = nullptr;
        checkMemoryConfig(aw, dw, block);
        require(page > 0, "Page size must be positive");
        auto model = std::make_unique<dcache::SparseMemory>(static_cast<std::size_t>(page));
        *h = model.get();
        memories.emplace(*h, std::move(model));
    });
}
extern "C" int sparse_mem_reset(void* h) {
    return protect([&] { lookup(memories, h).reset(); });
}
extern "C" int sparse_mem_destroy(void* h) {
    return protect([&] { require(memories.erase(h) == 1, "Invalid memory handle"); });
}
extern "C" int sparse_mem_write_line(void* h, uint32_t addr, const uint32_t* data) {
    return protect([&] {
        require(data != nullptr, "Null line input");
        dcache::Line line{};
        std::copy_n(data, dcache::WORDS_PER_BLOCK, line.begin());
        lookup(memories, h).writeLine(addr, line);
    });
}
extern "C" int sparse_mem_read_line(void* h, uint32_t addr, uint32_t* data) {
    return protect([&] {
        require(data != nullptr, "Null line output");
        const auto line = lookup(memories, h).readLine(addr);
        std::copy(line.begin(), line.end(), data);
    });
}
