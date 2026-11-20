#include "mshr_dpi.h"
#include <algorithm>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>

// 保留原模型断言，将失败转换成DPI状态和错误文本，避免assert直接终止整个仿真进程。
#define DCACHE_MSHR_ASSERT(x) do { if (!(x)) throw std::runtime_error("MSHR model assertion: " #x); } while (0)
#include "../../RefModel/Cache/MSHR.hpp"
#include "../../RefModel/MEM/SparseMemory.hpp"

namespace {
thread_local std::string last_error;
std::unordered_map<void*, std::unique_ptr<dcache::MSHR>> references;
std::unordered_map<void*, std::unique_ptr<dcache::SparseMemory>> memories;

// 统一转换C++异常。成功清除旧错误；失败后调用方必须停止使用输出并立即读取错误文本。
// 模型调用不是事务回滚接口，发生失败后应终止该次验证或显式重新初始化。
template<class F> int protect(F action) noexcept {
    try {
        action();
        last_error.clear();
        return 1;
    } catch (const std::exception& error) {
        last_error = error.what();
    } catch (...) {
        last_error = "Unknown C++ model failure";
    }
    return 0;
}

// 将参数和输入契约错误抛给protect处理，不让非法索引进入原模型。
void require(bool condition, const char* message) {
    if (!condition) {
        throw std::invalid_argument(message);
    }
}

// 根据已登记句柄获取对应C++实例；拒绝空句柄、其他类型句柄或已销毁对象。
template<class T> T& lookup(std::unordered_map<void*, std::unique_ptr<T>>& objects, void* handle) {
    const auto found = objects.find(handle);
    require(found != objects.end(), "Invalid or destroyed C++ model handle");
    return *found->second;
}

// 当前Line元素和Addr为32位；核对SV传参，禁止将其他字宽的packed数组误解释成此布局。
void checkMemoryConfig(int aw, int dw, int block) {
    require(aw == dcache::ADDR_WIDTH && dw == dcache::DATA_WIDTH &&
        block == dcache::BLOCK_SIZE && dw == 32,
        "SV and C++ memory parameters differ or packed word width is unsupported");
}

// 检查传入的无符号字段是否能够放入规定的位宽，避免32位移位的未定义行为。
bool fitsWidth(uint32_t value, int width) {
    return width >= 32 || (width > 0 && value < (uint32_t(1) << width));
}

// 查询口始终有效，所以即使没有alloc/merge，也检查tag和index的合法范围。
void checkQuery(uint32_t tag, uint32_t index) {
    require(fitsWidth(tag, dcache::TAG_WIDTH), "Query tag out of range");
    require(index < dcache::NUM_SETS, "Query index out of range");
}

// 检查新Slot的字偏移和CPU ID；完成replay的旧Slot不再占用CPU ID。
void checkSlot(const dcache::MSHR& model, uint32_t word_off, uint32_t resp_id) {
    require(word_off < dcache::WORDS_PER_BLOCK, "Slot word offset out of range");
    require(resp_id < dcache::CPU_ID_LIMIT, "Slot CPU ID out of range");
    for (int i = 0; i < dcache::MSHR_ENTRIES; ++i) {
        const auto& entry = model.entry(i);
        if (!entry.valid) {
            continue;
        }
        for (int s = entry.replayCnt; s < entry.validCnt; ++s) {
            require(entry.slots[s].respID != resp_id, "CPU ID reused before replay acceptance");
        }
    }
}

// alloc使用沿前资源：必须有空Entry，同块和同set/way不能已经被有效Entry占用。
void checkAlloc(const dcache::MSHR& model, const dcache::MSHR::AllocReq& request) {
    if (!request.en) {
        return;
    }
    require(model.hasFree(), "Allocation while MSHR has no free entry");
    checkQuery(request.tag, static_cast<uint32_t>(request.index));
    require(request.allocWay >= 0 && request.allocWay < dcache::NUM_WAYS, "Allocation way out of range");
    require(!model.match(request.tag, request.index).hit, "Duplicate allocated block address");
    require(request.wbSlotIdx == -1 ||
        (request.wbSlotIdx >= 0 && request.wbSlotIdx < dcache::WBB_ENTRIES), "Allocation WBB slot out of range");
    checkSlot(model, static_cast<uint32_t>(request.wordOff), request.respID);
    for (int i = 0; i < dcache::MSHR_ENTRIES; ++i) {
        const auto& entry = model.entry(i);
        require(!entry.valid || entry.index != request.index || entry.allocWay != request.allocWay,
            "Two active MSHR entries cannot own the same set and way");
    }
}

// merge必须指向沿前SEND/MISS_WAIT且仍有空Slot的Entry；响应同拍不会改变此前提。
void checkMerge(const dcache::MSHR& model, const dcache::MSHR::MergeReq& request) {
    if (!request.en) {
        return;
    }
    require(request.entry >= 0 && request.entry < dcache::MSHR_ENTRIES, "Merge entry out of range");
    const auto& entry = model.entry(request.entry);
    require(entry.valid && (entry.state == dcache::MSHR::State::SEND ||
        entry.state == dcache::MSHR::State::MISS_WAIT), "Merge requires SEND or MISS_WAIT entry");
    require(entry.validCnt < dcache::MSHR_MAX_PENDING, "Merge while entry slots are full");
    checkSlot(model, static_cast<uint32_t>(request.wordOff), request.respID);
}

// 响应使用完整总线ID验证归属，不能先截低位再接受未知高位或重复/提前响应。
void checkResponse(const dcache::MSHR& model, bool response_fire, uint32_t id) {
    if (!response_fire) {
        return;
    }
    require(id < dcache::MSHR_ENTRIES, "Read response ID is not a canonical MSHR entry ID");
    const auto& entry = model.entry(static_cast<int>(id));
    require(entry.valid && entry.state == dcache::MSHR::State::MISS_WAIT,
        "Read response requires an already issued and unanswered request");
}

// 原模型只公开hasFree和entry观察接口；读取首个空位以导出其现有最低下标选择结果。
// 这里只读取C++参考对象，不访问DUT内部信号，也不改变模型的分配策略。
int freeEntry(const dcache::MSHR& model) {
    for (int i = 0; i < dcache::MSHR_ENTRIES; ++i) {
        if (!model.entry(i).valid) {
            return i;
        }
    }
    return -1;
}
}

// 读取本线程最近一次DPI失败信息；字符串由适配层持有，不需要SV释放。
extern "C" const char* mshr_dpi_last_error() {
    return last_error.c_str();
}

// 创建原有C++ MSHR并核对全部接口相关常量；不会按SV参数动态改写模型常量。
extern "C" int mshr_ref_create(int aw, int dw, int block, int entries, int pending, int sets, int ways, int tagw, int indexw, int wayw, int wordoffw, int entryw, int slotw, int cpuw, int busw, int wbb_entries, int wbb_slotw, void** handle) {
    return protect([&] {
        require(handle != nullptr, "Null MSHR handle output");
        *handle = nullptr;
        checkMemoryConfig(aw, dw, block);
        require(entries == dcache::MSHR_ENTRIES && pending == dcache::MSHR_MAX_PENDING &&
            sets == dcache::NUM_SETS && ways == dcache::NUM_WAYS &&
            wbb_entries == dcache::WBB_ENTRIES, "SV and C++ MSHR capacities differ");
        require(tagw == dcache::TAG_WIDTH && indexw == dcache::INDEX_WIDTH &&
            wayw == std::max(1, dcache::clog2(dcache::NUM_WAYS)) &&
            wordoffw == std::max(1, dcache::WORD_OFF_WIDTH) &&
            entryw == std::max(1, dcache::MSHR_ID_WIDTH) &&
            slotw == std::max(1, dcache::clog2(dcache::MSHR_MAX_PENDING)) &&
            cpuw == dcache::ID_WIDTH && busw == std::max(1, dcache::BUS_ID_WIDTH) &&
            wbb_slotw == std::max(1, dcache::WBB_ID_WIDTH), "SV and C++ MSHR field widths differ");
        auto model = std::make_unique<dcache::MSHR>();
        *handle = model.get();
        references.emplace(*handle, std::move(model));
    });
}

// 调用RefModel/Cache/MSHR.hpp中的reset；不会清后端内存或SV请求记录。
extern "C" int mshr_ref_reset(void* handle) {
    return protect([&] { lookup(references, handle).reset(); });
}

// 销毁已登记的C++ MSHR对象，成功后调用方不应继续使用旧句柄。
extern "C" int mshr_ref_destroy(void* handle) {
    return protect([&] { require(references.erase(handle) == 1, "Invalid MSHR handle on destroy"); });
}

// 查询原模型validEntries；empty是结果，返回的int仍是调用状态，不推进模型。
extern "C" int mshr_ref_empty(void* handle, int* empty) {
    return protect([&] {
        require(empty != nullptr, "Null empty output");
        *empty = lookup(references, handle).validEntries() == 0;
    });
}

// 一次输入快照对应一次模型tick。先检查沿前输入合法性，再读取全部沿前预测。
// sendReq/fillReq会记录本拍已呈现，统一在这里各调用一次，其他SV组件不能重复读取推进。
// 同拍响应与merge使用原模型的沿前状态语义；同拍首次send和对应response暂不作为正常输入。
extern "C" int mshr_ref_step(void* handle,
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
    uint32_t* replay_payload_rData) {
    return protect([&] {
        require(resp_line && hasFree && freeEntry && m0_hit && m0_entry &&
            m0_mergeable && m0_slotFree && m0_freeSlot && m1_hit && m1_entry &&
            m1_mergeable && m1_slotFree && m1_freeSlot && memReadReq_valid && memReadReq_payload_addr &&
            memReadReq_payload_id && fill_en && fill_tag && fill_index && fill_way &&
            fill_dirty && fill_line && replay_valid && replay_payload_isWrite && replay_payload_id &&
            replay_payload_rData, "Null MSHR step output/input argument");
        auto& model = lookup(references, handle);
        require(!(alloc_en && merge_en), "Simultaneous alloc and merge are not supported by the current model contract");
        checkQuery(q0_tag, q0_index);
        checkQuery(q1_tag, q1_index);

        model.alloc_req = {};
        if (alloc_en) {
            require(!alloc_has_wb || alloc_wb_slot < dcache::WBB_ENTRIES,
                "Enabled allocation WBB slot out of range");
            model.alloc_req = {true, alloc_tag, static_cast<int>(alloc_index), static_cast<int>(alloc_way),
                alloc_is_write != 0, alloc_wdata, static_cast<int>(alloc_word_off), alloc_resp_id,
                alloc_has_wb ? static_cast<int>(alloc_wb_slot) : -1};
        }
        model.merge_req = {};
        if (merge_en) {
            model.merge_req = {true, static_cast<int>(merge_entry), merge_is_write != 0,
                merge_wdata, static_cast<int>(merge_word_off), merge_resp_id};
        }
        checkAlloc(model, model.alloc_req);
        checkMerge(model, model.merge_req);
        checkResponse(model, resp_fire != 0, resp_id);

        model.mem_rd_ready = send_ready != 0;
        model.fill_ready = fill_ready != 0;
        model.replay_ready = replay_ready != 0;
        model.mem_rd_resp = {};
        if (resp_fire) {
            model.mem_rd_resp.en = true;
            model.mem_rd_resp.id = resp_id;
            std::copy_n(resp_line, dcache::WORDS_PER_BLOCK, model.mem_rd_resp.line.begin());
        }

        // 下面是已有C++模型的公开组合输出；先读取预测，再更新时钟状态。
        const auto q0 = model.match(q0_tag, static_cast<int>(q0_index));
        const auto q1 = model.match(q1_tag, static_cast<int>(q1_index));
        const auto send = model.sendReq();
        const auto fill = model.fillReq();
        const auto replay = model.replayReq();
        *hasFree = model.hasFree();
        *freeEntry = ::freeEntry(model);
        *m0_hit = q0.hit;
        *m0_entry = q0.entry;
        *m0_mergeable = q0.mergeable;
        *m0_slotFree = q0.slotFree;
        *m0_freeSlot = q0.freeSlot;
        *m1_hit = q1.hit;
        *m1_entry = q1.entry;
        *m1_mergeable = q1.mergeable;
        *m1_slotFree = q1.slotFree;
        *m1_freeSlot = q1.freeSlot;
        *memReadReq_valid = send.en;
        *memReadReq_payload_addr = send.addr;
        *memReadReq_payload_id = send.id;
        *fill_en = fill.en;
        *fill_tag = fill.tag;
        *fill_index = static_cast<uint32_t>(fill.index);
        *fill_way = static_cast<uint32_t>(fill.way);
        *fill_dirty = fill.dirty;
        std::copy(fill.line.begin(), fill.line.end(), fill_line);
        *replay_valid = replay.en;
        *replay_payload_isWrite = replay.isWrite;
        *replay_payload_id = replay.respID;
        *replay_payload_rData = replay.rData;

        // tick()实现在RefModel/Cache/MSHR.hpp；本适配层不重新实现状态迁移或数据合并。
        model.tick();
    });
}

// 创建纯C++稀疏内存；它只存储后端原始数据，响应调度由SV memory driver负责。
extern "C" int mshr_mem_create(int page_size, int aw, int dw, int block, void** handle) {
    return protect([&] {
        require(handle != nullptr, "Null memory handle output");
        *handle = nullptr;
        checkMemoryConfig(aw, dw, block);
        require(page_size > 0, "Memory page size must be positive");
        // SparseMemory定义位于RefModel/MEM/SparseMemory.hpp，按写入按需分配页面。
        auto memory = std::make_unique<dcache::SparseMemory>(static_cast<std::size_t>(page_size));
        *handle = memory.get();
        memories.emplace(*handle, std::move(memory));
    });
}

// 清除指定C++稀疏内存内容；MSHR的普通复位不自动调用这个函数。
extern "C" int mshr_mem_reset(void* handle) {
    return protect([&] { lookup(memories, handle).reset(); });
}

// 销毁C++稀疏内存及全部页面；调用方成功后清除SV句柄。
extern "C" int mshr_mem_destroy(void* handle) {
    return protect([&] { require(memories.erase(handle) == 1, "Invalid memory handle on destroy"); });
}

// 把SV packed行按低32位字在前复制成原有C++ Line，再由SparseMemory::writeLine写入。
extern "C" int mshr_mem_write_line(void* handle, uint32_t addr, const uint32_t* data) {
    return protect([&] {
        require(data != nullptr, "Null memory line input");
        dcache::Line line{};
        std::copy_n(data, dcache::WORDS_PER_BLOCK, line.begin());
        lookup(memories, handle).writeLine(addr, line);
    });
}

// 从SparseMemory::readLine取出原始整行；内存代理在请求握手时保存返回值作为响应快照。
extern "C" int mshr_mem_read_line(void* handle, uint32_t addr, uint32_t* data) {
    return protect([&] {
        require(data != nullptr, "Null memory line output");
        const auto line = lookup(memories, handle).readLine(addr);
        std::copy(line.begin(), line.end(), data);
    });
}
