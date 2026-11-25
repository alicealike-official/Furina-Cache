// 调用已有C++ CacheTop与SparseMemory；本文件只做DPI数据转换和异常报告。
#include <svdpi.h>
#include <string>
#include <stdexcept>
#include "../../RefModel/Cache/CacheTop.hpp"
#include "../../RefModel/MEM/SparseMemory.hpp"
namespace {
thread_local std::string last_error;
// 按SV开放数组索引取32位值，避免假定模拟器数组内存布局。
unsigned get(const svOpenArrayHandle values, int index) {
    return *static_cast<unsigned*>(svGetArrElemPtr1(values, index));
}
// 按索引写入模型输出的ABI缓冲。
void put(const svOpenArrayHandle values, int index, unsigned value) {
    *static_cast<unsigned*>(svGetArrElemPtr1(values, index)) = value;
}
}
extern "C" const char* dcache_last_error() { return last_error.c_str(); }
extern "C" void* dcache_ref_create() {
    static_assert(dcache::DATA_WIDTH == 32 && dcache::ADDR_WIDTH == 32 && dcache::BLOCK_SIZE == 64 &&
        dcache::ID_WIDTH == 5 && dcache::BUS_ID_WIDTH == 4 && dcache::NUM_SETS == 32 &&
        dcache::NUM_WAYS == 4 && dcache::MSHR_ENTRIES == 4 && dcache::MSHR_MAX_PENDING == 4 &&
        dcache::WBB_ENTRIES == 4 && dcache::RESP_QUEUE_DEPTH == 4, "DCache framework configuration mismatch");
    try { return new dcache::CacheTop; }
    catch (const std::exception& error) { last_error = error.what(); return nullptr; }
}
extern "C" void dcache_ref_destroy(void* handle) { delete static_cast<dcache::CacheTop*>(handle); }
extern "C" int dcache_ref_step(void* handle, svBit reset_active, const svOpenArrayHandle inputs, const svOpenArrayHandle outputs) {
    try {
        if (!handle) throw std::runtime_error("Null CacheTop handle");
        auto& model = *static_cast<dcache::CacheTop*>(handle);
        if (reset_active) { model.reset(); return 1; }
        model.cpu_valid = get(inputs, 0);
        model.cpu_addr = get(inputs, 2);
        model.cpu_wrEn = get(inputs, 3);
        model.cpu_wData = get(inputs, 4);
        model.cpu_id = get(inputs, 5);
        model.cpuReadResp_ready = get(inputs, 7);
        model.cpuWriteResp_ready = get(inputs, 11);
        model.memReadReq_ready = get(inputs, 14);
        model.memWriteReq_ready = get(inputs, 18);
        model.memReadResp_valid = get(inputs, 37);
        for (int word = 0; word < 16; ++word) model.memReadResp_line[word] = get(inputs, 39 + word);
        model.memReadResp_id = get(inputs, 55);
        model.memWriteResp_valid = get(inputs, 56);
        model.memWriteResp_id = get(inputs, 58);
        model.eval();
        put(outputs, 1, model.cpu_ready);
        put(outputs, 6, model.cpuReadResp_valid);
        put(outputs, 8, model.cpuReadResp_rData);
        put(outputs, 9, model.cpuReadResp_id);
        put(outputs, 10, model.cpuWriteResp_valid);
        put(outputs, 12, model.cpuWriteResp_id);
        put(outputs, 13, model.memReadReq_valid);
        put(outputs, 15, model.memReadReq_addr);
        put(outputs, 16, model.memReadReq_id);
        put(outputs, 17, model.memWriteReq_valid);
        put(outputs, 19, model.memWriteReq_addr);
        for (int word = 0; word < 16; ++word) put(outputs, 20 + word, model.memWriteReq_line[word]);
        put(outputs, 36, model.memWriteReq_id);
        model.tick();
        return 1;
    } catch (const std::exception& error) { last_error = error.what(); return 0; }
}
extern "C" void* dcache_mem_create() {
    try { return new dcache::SparseMemory; }
    catch (const std::exception& error) { last_error = error.what(); return nullptr; }
}
extern "C" void dcache_mem_destroy(void* handle) { delete static_cast<dcache::SparseMemory*>(handle); }
extern "C" int dcache_mem_read(void* handle, unsigned addr, svBitVecVal* data) {
    try {
        if (!handle) throw std::runtime_error("Null SparseMemory handle");
        const auto line = static_cast<dcache::SparseMemory*>(handle)->readLine(addr);
        for (int word = 0; word < 16; ++word) data[word] = line[word];
        return 1;
    } catch (const std::exception& error) { last_error = error.what(); return 0; }
}
extern "C" int dcache_mem_write(void* handle, unsigned addr, const svBitVecVal* data) {
    try {
        if (!handle) throw std::runtime_error("Null SparseMemory handle");
        dcache::Line line{};
        for (int word = 0; word < 16; ++word) line[word] = data[word];
        static_cast<dcache::SparseMemory*>(handle)->writeLine(addr, line);
        return 1;
    } catch (const std::exception& error) { last_error = error.what(); return 0; }
}

namespace {
// 仅导出原策略的状态用于比较；touch/getVictim/onHit/onFill均沿用原实现。
class ObservableFifo : public dcache::FifoPolicy {
public:
    void exportOrder(svBitVecVal* result) const {
        for (int word = 0; word < 8; ++word) result[word] = 0;
        for (int set = 0; set < 32; ++set)
            for (int way = 0; way < 4; ++way)
                result[set / 4] |= unsigned(order_[set][way]) << ((set % 4) * 8 + way * 2);
    }
};
}
extern "C" void* dcache_fifo_create() {
    try { return new ObservableFifo; }
    catch (const std::exception& error) { last_error = error.what(); return nullptr; }
}
extern "C" void dcache_fifo_destroy(void* handle) {
    delete static_cast<ObservableFifo*>(handle);
}
extern "C" int dcache_fifo_step(void* handle, svBit reset_active, svBit hit,
    int hit_set, int hit_way, svBit fill, int fill_set, int fill_way,
    int query_set, int valid_mask, int lock_mask, int* candidate, svBitVecVal* order) {
    try {
        if (!handle) throw std::runtime_error("Null FIFO policy handle");
        auto& model = *static_cast<ObservableFifo*>(handle);
        if (reset_active) model.reset();
        if (query_set < 0 || query_set >= 32 || (hit && (hit_set < 0 || hit_set >= 32 || hit_way < 0 || hit_way >= 4)) ||
            (fill && (fill_set < 0 || fill_set >= 32 || fill_way < 0 || fill_way >= 4)))
            throw std::runtime_error("Invalid FIFO policy observation");
        std::array<bool,4> valid{},locked{};
        for (int way = 0; way < 4; ++way) { valid[way] = (valid_mask >> way) & 1; locked[way] = (lock_mask >> way) & 1; }
        *candidate = model.getVictim(query_set, valid, locked);
        model.exportOrder(order);
        if (hit) model.onHit(hit_set, hit_way);
        if (fill) model.onFill(fill_set, fill_way);
        return 1;
    } catch (const std::exception& error) { last_error = error.what(); return 0; }
}

namespace {
struct CacheMemReference {
    dcache::CacheMem model;
    unsigned compare_r1 = 0;
    unsigned known_r1 = 0;
    bool compare_r2 = false;
};
}
extern "C" void* dcache_memref_create() {
    try { return new CacheMemReference; }
    catch (const std::exception& error) { last_error = error.what(); return nullptr; }
}
extern "C" void dcache_memref_destroy(void* handle) {
    delete static_cast<CacheMemReference*>(handle);
}
extern "C" int dcache_memref_step(void* handle, svBit reset_active,
    const svOpenArrayHandle inputs, const svOpenArrayHandle outputs) {
    try {
        if (!handle) throw std::runtime_error("Null CacheMem reference");
        auto& state = *static_cast<CacheMemReference*>(handle);
        auto& model = state.model;
        if (reset_active) { model.reset(); state.compare_r1 = 0; state.known_r1 = 0; state.compare_r2 = false; return 1; }
        for (int way = 0; way < 4; ++way) {
            put(outputs, way*4, model.r1_resp.tag[way]);
            put(outputs, way*4+1, model.r1_resp.valid[way]);
            put(outputs, way*4+2, model.r1_resp.dirty[way]);
            put(outputs, way*4+3, model.r1_resp.data[way]);
        }
        for (int word = 0; word < 16; ++word) put(outputs, 16+word, model.r2_resp.line[word]);
        unsigned valid = 0, dirty = 0;
        const unsigned query_set = get(inputs, 35);
        if (query_set >= 32) throw std::runtime_error("Invalid inspect set");
        for (int way = 0; way < 4; ++way) {
            valid |= unsigned(model.getValid(query_set,way)) << way;
            dirty |= unsigned(model.getDirty(query_set,way)) << way;
        }
        put(outputs,32,valid); put(outputs,33,dirty);
        put(outputs,34,state.compare_r1); put(outputs,35,state.known_r1); put(outputs,36,state.compare_r2);
        for (int word = 0; word < 4; ++word) { put(outputs,37+word,0); put(outputs,41+word,0); }
        for (int set = 0; set < 32; ++set) {
            for (int way = 0; way < 4; ++way) {
                const int position = set*4+way;
                put(outputs,37+position/32,get(outputs,37+position/32) | (unsigned(model.getValid(set,way)) << (position%32)));
                put(outputs,41+position/32,get(outputs,41+position/32) | (unsigned(model.getDirty(set,way)) << (position%32)));
                put(outputs,45+position,model.getTag(set,way));
            }
        }
        model.r1_req = {bool(get(inputs,0)),int(get(inputs,1)),int(get(inputs,2))};
        model.r2_req = {bool(get(inputs,3)),int(get(inputs,4)),int(get(inputs,5))};
        model.w1_req = {bool(get(inputs,6)),int(get(inputs,7)),int(get(inputs,8)),int(get(inputs,9)),get(inputs,10)};
        model.w2_req.en = get(inputs,11); model.w2_req.index = get(inputs,12); model.w2_req.way = get(inputs,13);
        model.w2_req.tag = get(inputs,14); model.w2_req.dirty = get(inputs,15);
        for (int word = 0; word < 16; ++word) model.w2_req.line[word] = get(inputs,16+word);
        model.clr_req = {bool(get(inputs,32)),int(get(inputs,33)),int(get(inputs,34))};
        state.compare_r1 = 0; state.known_r1 = 0;
        for (int way = 0; way < 4; ++way) {
            const int set = model.r1_req.index;
            bool collision = (model.w1_req.en && model.w1_req.index == set && model.w1_req.way == way) ||
                (model.w2_req.en && model.w2_req.index == set && model.w2_req.way == way) ||
                (model.clr_req.en && model.clr_req.index == set && model.clr_req.way == way);
            if (model.r1_req.en && !collision) {
                state.compare_r1 |= 1u << way;
                if (model.getValid(set,way)) state.known_r1 |= 1u << way;
            }
        }
        const int read_set = model.r2_req.index, read_way = model.r2_req.way;
        state.compare_r2 = model.r2_req.en && model.getValid(read_set,read_way) &&
            !(model.w1_req.en && model.w1_req.index==read_set && model.w1_req.way==read_way) &&
            !(model.w2_req.en && model.w2_req.index==read_set && model.w2_req.way==read_way);
        model.tick();
        return 1;
    } catch (const std::exception& error) { last_error = error.what(); return 0; }
}
