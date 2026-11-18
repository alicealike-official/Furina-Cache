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

// 执行一次模型操作，将 C++ 异常转成 DPI 的返回状态，供 SV 检查。
// 成功返回 1 并清空错误字符串，失败返回 0 并保存原因；仅成功时才能使用本次输出。
// 已经执行的模型修改不会自动回滚，调用方应将失败作为验证错误处理。
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

// 检查适配层参数或调用前提；条件不成立时抛出异常，交由外层 protect() 转为失败状态。
void require(bool condition, const char* message) {
    if (!condition) throw std::invalid_argument(message);
}

// 用 SV 传入的 chandle 查找已注册的 C++ 模型实例并返回引用。
// 空句柄、已销毁句柄或不属于该模型类型的句柄均会报错。
template<class T> T& lookup(std::unordered_map<void*, std::unique_ptr<T>>& objects, void* h) {
    auto it = objects.find(h);
    require(it != objects.end(), "Invalid or destroyed model handle");
    return *it->second;
}

// 核对 SV 的地址宽度、字宽和行字节数是否与 RefModel/Cache/params.hpp 一致。
// 这里只校验配置，模型的编译期参数不会因传入这些值而改变。
void checkMemoryConfig(int aw, int dw, int block) {
    require(aw == dcache::ADDR_WIDTH && dw == dcache::DATA_WIDTH && block == dcache::BLOCK_SIZE,
        "SV and C++ memory parameters differ");
}
}

// 供 SV 在 DPI 返回 0 后读取本线程最近一次失败原因，读取本身不会清除错误。
// 成功的模型调用会清空该字符串，下一次失败会覆盖它，因此应在失败后立即读取。
// 返回字符串由适配层管理，调用方无需释放。
extern "C" const char* wbb_dpi_last_error() { return error.c_str(); }

// 创建已有 dcache::WriteBackBuffer 参考模型，并通过 h 返回供 SV 保存的 chandle。
// 检查地址宽、字宽、行大小、槽数、槽 ID 宽和总线 ID 宽与 C++ 配置一致。
// 成功返回 1，调用方后续负责用 wbb_ref_destroy() 释放该实例。
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

// 调用指定 WBB 实例的 reset()，清除槽状态和输入端口，保留句柄供后续周期使用。
// 此操作只复位 WBB 模型，关联的内存数据和 SV 响应队列由各自所有者管理。
extern "C" int wbb_ref_reset(void* h) {
    return protect([&] { lookup(refs, h).reset(); });
}

// 从实例表中移除并销毁 WBB 模型；成功后原句柄失效，SV 应将自己的 chandle 置 null。
extern "C" int wbb_ref_destroy(void* h) {
    return protect([&] { require(refs.erase(h) == 1, "Invalid WBB handle"); });
}

// 查询 WBB 是否排空：任一槽存在 valid、reserved 或 issued 时，输出 empty=0，否则为 1。
// 函数返回值表示调用是否成功，实际的排空结果通过 empty 输出；不推进模型时钟。
extern "C" int wbb_ref_empty(void* h, int* empty) {
    return protect([&] {
        require(empty != nullptr, "Null empty output");
        auto& model = lookup(refs, h);
        *empty = 1;
        for (int i = 0; i < dcache::WBB_ENTRIES; ++i)
            if (model.getValid(i) || model.getReserved(i) || model.getIssued(i)) *empty = 0;
    });
}

// 消费一个采样沿的 WBB 输入，生成同一沿的预测输出，再推进一次参考模型 tick()。
// reserve_en/addr、push_en/slot/line、send_ready、q0/q1 来自 monitor 的当前拍快照。
// resp_valid 在 SV 调用处已转换为 memWriteResp_valid && memWriteResp_ready，表示响应被接受。
// 输出 reserve_ok/slot、full、q0/q1_same 和 send_valid/addr/data/id 均取自 tick() 之前的状态。
// reserve_ok 表示沿前有空槽；为 0 时 reserve_slot 无效。send_valid 为 0 时忽略发送载荷。
// packed 行以低位 32-bit 字在前传入/传出，分别对应 C++ Line[0]、Line[1] 等。
// 成功返回后模型已进入沿后状态；SV 将返回的沿前预测与原采样配对比较，每拍只调用一次。
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

// 创建一份独立的 dcache::SparseMemory，核对 SV/C++ 位宽及行大小，使用 page 指定页字节数。
// 页面大小必须是正的 2 次幂；初始逻辑内存读零，实际写入时按需分配页面。
// h 返回实例句柄；实际内存和期望内存分别调用本函数创建，存储内容互相独立。
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

// 清空指定稀疏内存实例，释放已分配页面，使其重新表现为全零内存；实例句柄仍有效。
extern "C" int sparse_mem_reset(void* h) {
    return protect([&] { lookup(memories, h).reset(); });
}

// 销毁指定稀疏内存及其页面，句柄随即失效；成功后 SV 应将自己的 chandle 置 null。
extern "C" int sparse_mem_destroy(void* h) {
    return protect([&] { require(memories.erase(h) == 1, "Invalid memory handle"); });
}

// 将 SV packed 行转换成 C++ Line，并在块对齐地址 addr 写入整行。
// data[0] 对应 SV 行总线最低 32 位，后续字依次排列；SparseMemory 负责字节序与跨页存储。
// 成功返回时存储内容已经更新；响应延迟及 ack 握手由 SV memory driver 管理。
extern "C" int sparse_mem_write_line(void* h, uint32_t addr, const uint32_t* data) {
    return protect([&] {
        require(data != nullptr, "Null line input");
        dcache::Line line{};
        std::copy_n(data, dcache::WORDS_PER_BLOCK, line.begin());
        lookup(memories, h).writeLine(addr, line);
    });
}

// 从块对齐地址 addr 读取整行，通过 data 返回 packed 字数组；未写区域返回零。
// data[0] 对应行总线最低 32 位。此接口用于验证侧回读实际/期望内存，不产生 DUT 总线事务。
extern "C" int sparse_mem_read_line(void* h, uint32_t addr, uint32_t* data) {
    return protect([&] {
        require(data != nullptr, "Null line output");
        const auto line = lookup(memories, h).readLine(addr);
        std::copy(line.begin(), line.end(), data);
    });
}
