// test_cachetop_full.cpp
// =============================================================
// CacheTop 完整测试（内部数据 + 控制状态 + 精确一次响应）
//
// 覆盖：
//   T1  读未命中：整行 16 字、tag/valid/dirty、MSHR 释放、WayLock、精确一次
//   T2  写命中：W1 数据、dirty、其余字不变、写命中不读内存
//   T3  同地址合并：只读一次内存、单条目 validCnt==2、两响应按序
//   T4  写分配合并：mergedData、dirty、重放读旁路、只读一次内存
//   T5  脏行淘汰：WBB 写回整行数据、victim 路复用、旧行失效
//   T6  干净行淘汰：不产生 WBB 写回
//   T7  hit-under-miss：miss 未完成时另一条命中可先返回
//   T8  MSHR 满：最多 4 条、第 5 条等待、最终全部完成、读次数精确
//   T9  WBB 同地址冲突：写回未完成时同线读被挡住，完成后读到新值
//   T10 FIFO 顺序：前 4 条按路 0..3 填充，之后按 FIFO 淘汰
//   T11 随机影子模型：每次操作后检查所有驻留行的 16 字数据
//
// 编译：
//   make run-cachetop-full
// =============================================================

#include "CacheTop.hpp"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <deque>
#include <iostream>
#include <map>
#include <random>
#include <vector>

using namespace dcache;

// -------------------------------------------------------------
// 确定性初始行（内存与测试共用）
// -------------------------------------------------------------
static Line makeInitialLine(Addr a) {
    Line l{};
    for (int i = 0; i < WORDS_PER_BLOCK; ++i) {
        l[i] = (static_cast<Word>(a) * 2654435761u) ^
               (static_cast<Word>(i) * 0x9E3779B9u) ^
               0xA5A5A5A5u;
    }
    return l;
}

static Word initialWord(Addr a) {
    const Addr base = a & ~OFFSET_MASK;   // 与 SimpleMem::readLine 的种子口径一致
    return makeInitialLine(base)[decodeWordOff(a)];
}

// -------------------------------------------------------------
// 行为级内存：读/写均有延迟；写响应时才真正写入
// -------------------------------------------------------------
struct SimpleMem {
    std::map<Addr, Line> mem;
    std::vector<Addr> readAddrs;
    std::vector<std::pair<Addr, Line>> writes;

    int rdLatency = 2;
    int wrLatency = 2;
    bool ooo = false;              // true：后完成的先返回（乱序）

    struct RdPend { int remain; Addr addr; BusId id; };
    struct WrPend { int remain; Addr addr; Line line; BusId id; };
    std::deque<RdPend> rdPend;
    std::deque<WrPend> wrPend;

    bool  rdRespValid = false;
    Line  rdRespLine{};
    BusId rdRespId = 0;

    bool  wrRespValid = false;
    BusId wrRespId = 0;

    Line readLine(Addr a) const {
        auto it = mem.find(a);
        return (it != mem.end()) ? it->second : makeInitialLine(a);
    }

    int readCount(Addr a) const {
        int n = 0;
        for (Addr x : readAddrs) if (x == a) ++n;
        return n;
    }

    // 测试辅助：让所有挂起的写先完成（用于解除 WBB 满造成的冻结）
    void drainWrites() {
        for (auto& p : wrPend) p.remain = 1;
    }

    void tick(bool rdV, Addr rdA, BusId rdId, bool rdR,
              bool wrV, Addr wrA, const Line& wrL, BusId wrId, bool wrR) {
        rdRespValid = false;
        wrRespValid = false;

        // 推进已有事务（可配置乱序返回；每拍最多一个读 + 一个写响应）
        {
            std::vector<int> done;
            for (int i = 0; i < static_cast<int>(rdPend.size()); ++i)
                if (--rdPend[i].remain <= 0) done.push_back(i);
            if (!done.empty()) {
                const int idx = ooo ? done.back() : done.front();
                rdRespValid = true;
                rdRespLine  = readLine(rdPend[idx].addr);
                rdRespId    = rdPend[idx].id;
                rdPend.erase(rdPend.begin() + idx);
            }
        }
        {
            std::vector<int> done;
            for (int i = 0; i < static_cast<int>(wrPend.size()); ++i)
                if (--wrPend[i].remain <= 0) done.push_back(i);
            if (!done.empty()) {
                const int idx = ooo ? done.back() : done.front();
                mem[wrPend[idx].addr] = wrPend[idx].line;
                writes.push_back({ wrPend[idx].addr, wrPend[idx].line });
                wrRespValid = true;
                wrRespId    = wrPend[idx].id;
                wrPend.erase(wrPend.begin() + idx);
            }
        }

        // 接收新事务
        if (rdV && rdR) {
            readAddrs.push_back(rdA);
            rdPend.push_back(RdPend{ rdLatency, rdA, rdId });
        }
        if (wrV && wrR) {
            wrPend.push_back(WrPend{ wrLatency, wrA, wrL, wrId });
        }
    }
};

// -------------------------------------------------------------
struct CpuReq { Addr addr; bool wr; Word wData; CpuId id; };

struct Harness {
    CacheTop top;
    SimpleMem mem;

    std::deque<CpuReq> reqs;
    std::vector<CacheTop::ReadResp>  rdResps;
    std::vector<CacheTop::WriteResp> wrResps;
    int cycles = 0;

    Harness() {
        top.memReadReq_ready   = true;
        top.memWriteReq_ready  = true;
        top.cpuReadResp_ready  = true;
        top.cpuWriteResp_ready = true;
    }

    void submit(Addr a, bool wr, Word wd, CpuId id) {
        // §3.4：激励必须落在 ID_WIDTH 位能表达的范围内（CpuId 的存储类型
        // 仍是 32 位，不做刻意收窄；约束施加在激励上）。
        assert(id < CPU_ID_LIMIT && "CPU ID 超出 ID_WIDTH 范围");
        reqs.push_back(CpuReq{ a, wr, wd, id });
    }

    void step() {
        if (!reqs.empty()) {
            top.cpu_valid = true;
            top.cpu_addr  = reqs.front().addr;
            top.cpu_wrEn  = reqs.front().wr;
            top.cpu_wData = reqs.front().wData;
            top.cpu_id    = reqs.front().id;
        } else {
            top.cpu_valid = false;
        }

        top.eval();
        const bool accepted = top.cpu_valid && top.cpu_ready;

        mem.tick(top.memReadReq_valid, top.memReadReq_addr, top.memReadReq_id,
                 top.memReadReq_ready,
                 top.memWriteReq_valid, top.memWriteReq_addr,
                 top.memWriteReq_line, top.memWriteReq_id,
                 top.memWriteReq_ready);

        top.memReadResp_valid = mem.rdRespValid;
        top.memReadResp_line  = mem.rdRespLine;
        top.memReadResp_id    = mem.rdRespId;
        top.memWriteResp_valid = mem.wrRespValid;
        top.memWriteResp_id    = mem.wrRespId;

        top.tick();

        if (top.cpuReadResp_valid && top.cpuReadResp_ready)
            rdResps.push_back(CacheTop::ReadResp{ top.cpuReadResp_rData,
                                                  top.cpuReadResp_id });
        if (top.cpuWriteResp_valid && top.cpuWriteResp_ready)
            wrResps.push_back(CacheTop::WriteResp{ top.cpuWriteResp_id });

        if (accepted) reqs.pop_front();
        ++cycles;
    }

    template <typename Pred>
    bool run_until(Pred pred, int maxCycles = 400) {
        for (int i = 0; i < maxCycles; ++i) {
            if (pred()) return true;
            step();
        }
        return pred();
    }

    void run_cycles(int n) { for (int i = 0; i < n; ++i) step(); }

    int findWay(int set, Tag tag) const {
        for (int w = 0; w < NUM_WAYS; ++w)
            if (top.cache().getValid(set, w) && top.cache().getTag(set, w) == tag)
                return w;
        return -1;
    }

    void expectLine(int set, int way, Tag tag, const Line& line, bool dirty) const {
        assert(way >= 0 && way < NUM_WAYS);
        assert(top.cache().getValid(set, way));
        assert(top.cache().getTag(set, way) == tag);
        assert(top.cache().getDirty(set, way) == dirty);
        for (int o = 0; o < WORDS_PER_BLOCK; ++o) {
            const Word got = top.cache().getWord(set, way, o);
            if (got != line[o]) {
                std::cerr << "\n[line mismatch] set=" << set << " way=" << way
                          << " word=" << o
                          << " got=0x" << std::hex << got
                          << " exp=0x" << line[o] << std::dec << "\n";
                assert(false);
            }
        }
    }

    bool mshrEmpty() const { return top.mshr().validEntries() == 0; }

    bool wbbEmpty() const {
        for (int i = 0; i < WBB_ENTRIES; ++i)
            if (top.wbb().getValid(i) || top.wbb().getReserved(i) ||
                top.wbb().getIssued(i))
                return false;
        return true;
    }

    bool allLocksFree() const {
        for (int s = 0; s < NUM_SETS; ++s)
            for (int w = 0; w < NUM_WAYS; ++w)
                if (top.locked(s, w)) return false;
        return true;
    }
};

// -------------------------------------------------------------
static Addr lineAddr(int tag, int set) {
    return (static_cast<Addr>(tag) << (INDEX_WIDTH + OFFSET_WIDTH)) |
           (static_cast<Addr>(set) << OFFSET_WIDTH);
}

// -------------------------------------------------------------
// T1：读未命中，检查整行
// -------------------------------------------------------------
static void test_read_miss_full() {
    std::cout << "[T1] 读未命中 / 整行数据 ... ";

    Harness h;
    const Addr A = 0x1000;
    const int  set = decodeIndex(A);
    const Tag  tag = decodeTag(A);
    const Line exp = h.mem.readLine(A);

    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));
    assert(h.rdResps[0].id == 1);
    assert(h.rdResps[0].rData == exp[decodeWordOff(A)]);

    h.run_cycles(3);

    const int way = h.findWay(set, tag);
    assert(way >= 0);
    h.expectLine(set, way, tag, exp, false);

    assert(h.mem.readCount(A) == 1);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());
    assert(h.wbbEmpty());

    h.run_cycles(5);
    assert(h.rdResps.size() == 1);   // 精确一次

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T2：写命中，检查 W1 数据与其余字
// -------------------------------------------------------------
static void test_write_hit_full() {
    std::cout << "[T2] 写命中 / 其余字不变 ... ";

    Harness h;
    const Addr A = 0x1000;
    const int  set = decodeIndex(A);
    const Tag  tag = decodeTag(A);
    const Line base = h.mem.readLine(A);

    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));
    h.run_cycles(2);
    const int way = h.findWay(set, tag);
    assert(way >= 0);

    const size_t readsBefore = h.mem.readAddrs.size();
    const Word W = 0xDEADBEEF;
    h.submit(A + 4, true, W, 2);
    assert(h.run_until([&] { return h.wrResps.size() == 1; }));
    assert(h.wrResps[0].id == 2);
    assert(h.mem.readAddrs.size() == readsBefore);   // 写命中不读内存

    assert(h.top.cache().getWord(set, way, 1) == W);
    assert(h.top.cache().getDirty(set, way));
    for (int o = 0; o < WORDS_PER_BLOCK; ++o)
        if (o != 1)
            assert(h.top.cache().getWord(set, way, o) == base[o]);

    h.submit(A + 4, false, 0, 3);
    assert(h.run_until([&] { return h.rdResps.size() == 2; }));
    assert(h.rdResps[1].id == 3);
    assert(h.rdResps[1].rData == W);

    h.run_cycles(5);
    assert(h.rdResps.size() == 2);
    assert(h.wrResps.size() == 1);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T3：同地址合并，检查单条目 + 单次内存读
// -------------------------------------------------------------
static void test_merge_full() {
    std::cout << "[T3] 同地址合并 / 单次内存读 ... ";

    Harness h;
    h.mem.rdLatency = 8;

    const Addr A = 0x2000;
    const Line exp = h.mem.readLine(A);

    h.submit(A, false, 0, 1);
    h.submit(A, false, 0, 2);

    bool sawMerge = false;
    for (int i = 0; i < 60; ++i) {
        h.step();
        if (h.top.mshr().validEntries() == 1 &&
            h.top.mshr().entry(0).validCnt == 2) {
            sawMerge = true;
            break;
        }
    }
    assert(sawMerge);
    assert(h.top.mshr().validEntries() == 1);

    assert(h.run_until([&] { return h.rdResps.size() == 2; }));
    assert(h.mem.readCount(A) == 1);                 // 合并 -> 只读一次

    assert(h.rdResps[0].id == 1);
    assert(h.rdResps[1].id == 2);
    assert(h.rdResps[0].rData == exp[decodeWordOff(A)]);
    assert(h.rdResps[1].rData == exp[decodeWordOff(A)]);

    h.run_cycles(4);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());
    assert(h.rdResps.size() == 2);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T4：写分配合并，检查 mergedData / dirty / 重放旁路
// -------------------------------------------------------------
static void test_write_allocate_merge() {
    std::cout << "[T4] 写分配合并 / mergedData ... ";

    Harness h;
    h.mem.rdLatency = 8;

    const Addr A = 0x3000;
    const int  set = decodeIndex(A);
    const Tag  tag = decodeTag(A);
    const Word W = 0xA5A5A5A5;
    const Line base = h.mem.readLine(A);

    // 写 miss + 同字读，后者应合并进同一条目
    h.submit(A + 4, true, W, 1);
    h.submit(A + 4, false, 0, 2);

    assert(h.run_until([&] {
        return h.wrResps.size() == 1 && h.rdResps.size() == 1;
    }));

    assert(h.wrResps[0].id == 1);
    assert(h.rdResps[0].id == 2);
    assert(h.rdResps[0].rData == W);      // 重放读旁路：前序写同字

    h.run_cycles(3);
    const int way = h.findWay(set, tag);
    assert(way >= 0);
    Line exp = base;
    exp[1] = W;
    h.expectLine(set, way, tag, exp, true);   // 有写 Slot -> dirty

    assert(h.mem.readCount(A) == 1);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T5：脏行淘汰，检查 WBB 写回整行数据
// -------------------------------------------------------------
static void test_dirty_evict_full() {
    std::cout << "[T5] 脏行淘汰 / 写回数据 ... ";

    Harness h;
    const int set = 0;
    const Addr A[5] = { 0x1000, 0x2000, 0x3000, 0x4000, 0x5000 };

    for (int i = 0; i < 4; ++i) {
        const size_t before = h.rdResps.size();
        h.submit(A[i], false, 0, static_cast<CpuId>(10 + i));
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
    }

    // 写脏 A0
    const Word W = 0xCAFEBABE;
    h.submit(A[0] + 4, true, W, 20);
    assert(h.run_until([&] { return h.wrResps.size() == 1; }));

    Line expA0 = h.mem.readLine(A[0]);
    expA0[1] = W;
    const Tag tag0 = decodeTag(A[0]);
    const int way0 = h.findWay(set, tag0);
    assert(way0 >= 0);

    // 第 5 条 miss -> 淘汰 way0
    const size_t rb = h.rdResps.size();
    h.submit(A[4], false, 0, 30);
    assert(h.run_until([&] { return h.rdResps.size() > rb; }));

    // 等 WBB 写回完成
    assert(h.run_until([&] { return !h.mem.writes.empty(); }, 300));
    assert(h.mem.writes[0].first == A[0]);
    for (int o = 0; o < WORDS_PER_BLOCK; ++o) {
        if (h.mem.writes[0].second[o] != expA0[o]) {
            std::cerr << "\n[writeback mismatch] word=" << o
                      << " got=0x" << std::hex << h.mem.writes[0].second[o]
                      << " exp=0x" << expA0[o] << std::dec << "\n";
            assert(false);
        }
    }

    // victim 路被 A4 复用；A0 失效
    const int way4 = h.findWay(set, decodeTag(A[4]));
    assert(way4 == way0);
    h.expectLine(set, way4, decodeTag(A[4]), h.mem.readLine(A[4]), false);
    assert(h.findWay(set, tag0) == -1);

    h.run_cycles(6);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());
    assert(h.wbbEmpty());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T6：干净行淘汰，不产生 WBB 写回
// -------------------------------------------------------------
static void test_clean_evict_full() {
    std::cout << "[T6] 干净行淘汰 / 无写回 ... ";

    Harness h;
    const int set = 0;
    const Addr A[5] = { 0x1000, 0x2000, 0x3000, 0x4000, 0x5000 };

    for (int i = 0; i < 4; ++i) {
        const size_t before = h.rdResps.size();
        h.submit(A[i], false, 0, static_cast<CpuId>(10 + i));
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
    }

    const size_t rb = h.rdResps.size();
    h.submit(A[4], false, 0, 30);
    assert(h.run_until([&] { return h.rdResps.size() > rb; }));
    h.run_cycles(6);

    assert(h.mem.writes.empty());                 // 干净 victim 不写回
    assert(h.wbbEmpty());
    assert(h.findWay(set, decodeTag(A[0])) == -1);
    assert(h.findWay(set, decodeTag(A[4])) >= 0);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T7：hit-under-miss
// -------------------------------------------------------------
static void test_hit_under_miss() {
    std::cout << "[T7] hit-under-miss ... ";

    Harness h;
    h.mem.rdLatency = 10;

    const Addr A = 0x1000;
    const Addr B = 0x2000;

    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));

    // 发起 B miss
    h.submit(B, false, 0, 2);
    h.run_cycles(3);

    // 在 B 未完成时读 A（应命中并先返回）
    h.submit(A, false, 0, 3);
    assert(h.run_until([&] { return h.rdResps.size() >= 3; }, 200));

    assert(h.rdResps[0].id == 1);   // A 初次 miss
    assert(h.rdResps[1].id == 3);   // A 命中
    assert(h.rdResps[2].id == 2);   // B miss 后返回

    assert(h.mem.readCount(A) == 1);   // A 命中不再读内存
    assert(h.mem.readCount(B) == 1);

    h.run_cycles(5);
    assert(h.rdResps.size() == 3);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T8：MSHR 满，第 5 条等待
// -------------------------------------------------------------
static void test_mshr_full() {
    std::cout << "[T8] MSHR 满 / 第 5 条等待 ... ";

    Harness h;
    h.mem.rdLatency = 20;

    const Addr A[5] = { 0x1000, 0x1040, 0x1080, 0x10C0, 0x1100 };
    for (int i = 0; i < 5; ++i)
        h.submit(A[i], false, 0, static_cast<CpuId>(i));

    for (int i = 0; i < 500; ++i) {
        h.step();
        assert(h.top.mshr().validEntries() <= MSHR_ENTRIES);
        if (h.rdResps.size() == 5) break;
    }

    assert(h.rdResps.size() == 5);
    assert(h.mem.readAddrs.size() == 5);      // 每条 miss 读一次

    std::vector<int> ids;
    for (const auto& r : h.rdResps) ids.push_back(static_cast<int>(r.id));
    std::sort(ids.begin(), ids.end());
    for (int i = 0; i < 5; ++i) assert(ids[i] == i);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T9：WBB 同地址冲突
// -------------------------------------------------------------
static void test_wbb_same_addr() {
    std::cout << "[T9] WBB 同地址冲突 ... ";

    Harness h;
    h.mem.rdLatency = 2;
    h.mem.wrLatency = 20;

    const Addr A[5] = { 0x1000, 0x2000, 0x3000, 0x4000, 0x5000 };
    for (int i = 0; i < 4; ++i) {
        const size_t before = h.rdResps.size();
        h.submit(A[i], false, 0, static_cast<CpuId>(10 + i));
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
    }

    const Word W = 0x12345678;
    h.submit(A[0] + 4, true, W, 20);
    assert(h.run_until([&] { return h.wrResps.size() == 1; }));

    // 淘汰 A0
    const size_t rb = h.rdResps.size();
    h.submit(A[4], false, 0, 30);
    assert(h.run_until([&] { return h.rdResps.size() > rb; }));

    // 等 WBB 的写回真正上路
    assert(h.run_until([&] { return !h.mem.wrPend.empty(); }, 200));

    // 同线读：应被 wbSameAddr 挡住，写回完成后读到 W
    const size_t rb2 = h.rdResps.size();
    h.submit(A[0] + 4, false, 0, 31);
    assert(h.run_until([&] { return h.rdResps.size() > rb2; }, 400));
    assert(h.rdResps.back().id == 31);
    assert(h.rdResps.back().rData == W);

    h.run_cycles(6);
    assert(h.wbbEmpty());
    assert(h.mshrEmpty());
    assert(h.allLocksFree());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T10：FIFO 顺序
// -------------------------------------------------------------
static void test_fifo_order() {
    std::cout << "[T10] FIFO 顺序 ... ";

    Harness h;
    const int set = 0;
    const Addr A[6] = { 0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 0x6000 };

    for (int i = 0; i < 4; ++i) {
        const size_t before = h.rdResps.size();
        h.submit(A[i], false, 0, static_cast<CpuId>(10 + i));
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
    }

    // 前 4 条按路 0..3 填充
    for (int i = 0; i < 4; ++i)
        assert(h.findWay(set, decodeTag(A[i])) == i);

    // 第 5 条淘汰 way0
    {
        const size_t before = h.rdResps.size();
        h.submit(A[4], false, 0, 20);
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
        assert(h.findWay(set, decodeTag(A[4])) == 0);
        assert(h.findWay(set, decodeTag(A[0])) == -1);
    }

    // 第 6 条淘汰 way1
    {
        const size_t before = h.rdResps.size();
        h.submit(A[5], false, 0, 21);
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
        assert(h.findWay(set, decodeTag(A[5])) == 1);
        assert(h.findWay(set, decodeTag(A[1])) == -1);
    }

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T11：随机影子模型（每次操作后检查所有驻留行）
// -------------------------------------------------------------
static void checkResidentLines(const Harness& h, const std::map<Addr, Word>& shadow) {
    for (int s = 0; s < NUM_SETS; ++s) {
        for (int w = 0; w < NUM_WAYS; ++w) {
            if (!h.top.cache().getValid(s, w)) continue;
            const Tag tag = h.top.cache().getTag(s, w);
            const Addr base = lineAddr(tag, s);
            for (int o = 0; o < WORDS_PER_BLOCK; ++o) {
                const Addr a = base + (static_cast<Addr>(o) << 2);
                const Word exp = shadow.count(a) ? shadow.at(a) : initialWord(a);
                const Word got = h.top.cache().getWord(s, w, o);
                if (got != exp) {
                    std::cerr << "\n[shadow mismatch] set=" << s << " way=" << w
                              << " addr=0x" << std::hex << a
                              << " got=0x" << got
                              << " exp=0x" << exp << std::dec << "\n";
                    assert(false);
                }
            }
        }
    }
}

static void test_random_shadow() {
    std::cout << "[T11] 随机影子模型 ... ";

    const int SEEDS[] = { 1, 12345, 999 };
    const int LINES   = 6;      // 每个 set 6 条热点行争用 4 路
    const int SETS    = 4;      // 覆盖 4 个 set
    const int OPS     = 150;

    for (int si = 0; si < 3; ++si) {
        Harness h;
        h.mem.rdLatency = 2;
        h.mem.wrLatency = 2;

        std::map<Addr, Word> shadow;
        std::mt19937 rng(SEEDS[si]);
        std::uniform_int_distribution<int> lineDist(0, LINES - 1);
        std::uniform_int_distribution<int> setDist(0, SETS - 1);
        std::uniform_int_distribution<int> wordDist(0, WORDS_PER_BLOCK - 1);
        std::uniform_int_distribution<int> opDist(0, 1);

        // 激励的 ID 必须落在 ID_WIDTH 范围内（§3.4）。本用例一次只发一条请求，
        // 收到响应后才发下一条，因此可以安全地循环复用 ID。
        CpuId id = 1;
        auto nextId = [&]() {
            const CpuId cur = id;
            id = (id + 1 == CPU_ID_LIMIT) ? 1 : id + 1;
            return cur;
        };
        int nReads = 0, nWrites = 0;

        for (int op = 0; op < OPS; ++op) {
            const Addr a = lineAddr(0x10 + lineDist(rng), setDist(rng)) +
                           (static_cast<Addr>(wordDist(rng)) << 2);
            const bool wr = opDist(rng) != 0;

            if (wr) {
                const Word w = static_cast<Word>(rng());
                const size_t before = h.wrResps.size();
                h.submit(a, true, w, nextId());
                ++nWrites;
                assert(h.run_until([&] { return h.wrResps.size() > before; }, 800));
                shadow[a] = w;
            } else {
                const Word exp = shadow.count(a) ? shadow.at(a) : initialWord(a);
                const size_t before = h.rdResps.size();
                h.submit(a, false, 0, nextId());
                ++nReads;
                assert(h.run_until([&] { return h.rdResps.size() > before; }, 800));

                const Word got = h.rdResps.back().rData;
                if (got != exp) {
                    const int  s    = decodeIndex(a);
                    const Tag  tg   = decodeTag(a);
                    const Addr base = a & ~OFFSET_MASK;
                    const int  w    = h.findWay(s, tg);

                    std::cerr << "\n[random mismatch] seed=" << SEEDS[si]
                              << " op=" << op
                              << " addr=0x" << std::hex << a << std::dec
                              << " wordOff=" << decodeWordOff(a)
                              << " id=" << h.rdResps.back().id
                              << " got=0x" << std::hex << got
                              << " exp=0x" << exp << std::dec << "\n";
                    std::cerr << "  set=" << s << " tag=0x" << std::hex << tg
                              << std::dec << " residentWay=" << w << "\n";

                    if (w >= 0) {
                        std::cerr << "  cache :";
                        for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                            std::cerr << " 0x" << std::hex
                                      << h.top.cache().getWord(s, w, o) << std::dec;
                        std::cerr << "\n";
                    }
                    std::cerr << "  mem   :";
                    const Line ml = h.mem.readLine(base);
                    for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                        std::cerr << " 0x" << std::hex << ml[o] << std::dec;
                    std::cerr << "\n  shadow:";
                    for (int o = 0; o < WORDS_PER_BLOCK; ++o) {
                        const Addr aa = base + (static_cast<Addr>(o) << 2);
                        const Word v = shadow.count(aa) ? shadow.at(aa)
                                                        : initialWord(aa);
                        std::cerr << " 0x" << std::hex << v << std::dec;
                    }
                    std::cerr << "\n  mshrEntries=" << h.top.mshr().validEntries()
                              << " wbbEmpty=" << h.wbbEmpty() << "\n";
                    assert(false);
                }
            }

            checkResidentLines(h, shadow);
        }

        // 排空 WBB / MSHR，并检查 WayLock 与响应精确一次
        assert(h.run_until([&] { return h.wbbEmpty() && h.mshrEmpty(); }, 2000));
        assert(h.allLocksFree());
        assert(static_cast<int>(h.rdResps.size()) == nReads);
        assert(static_cast<int>(h.wrResps.size()) == nWrites);
        checkResidentLines(h, shadow);
    }

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T12：乱序读响应
// -------------------------------------------------------------
static void test_ooo_read_responses() {
    std::cout << "[T12] 乱序读响应 ... ";

    Harness h;
    h.mem.rdLatency = 6;
    h.mem.ooo = true;

    const Addr A[4] = { 0x1000, 0x1040, 0x1080, 0x10C0 };
    Line exp[4];
    for (int i = 0; i < 4; ++i) {
        exp[i] = h.mem.readLine(A[i]);
        h.submit(A[i], false, 0, static_cast<CpuId>(i));
    }

    assert(h.run_until([&] { return h.rdResps.size() == 4; }, 400));

    // 按 ID 检查数据，不假设返回顺序
    std::vector<bool> seen(4, false);
    for (const auto& r : h.rdResps) {
        const int i = static_cast<int>(r.id);
        assert(i >= 0 && i < 4);
        assert(!seen[i]);
        seen[i] = true;
        assert(r.rData == exp[i][decodeWordOff(A[i])]);
    }
    for (int i = 0; i < 4; ++i) assert(seen[i]);

    // 每条行都应正确填入
    h.run_cycles(5);
    for (int i = 0; i < 4; ++i) {
        const int s = decodeIndex(A[i]);
        const Tag t = decodeTag(A[i]);
        const int w = h.findWay(s, t);
        assert(w >= 0);
        h.expectLine(s, w, t, exp[i], false);
    }
    assert(h.mshrEmpty());
    assert(h.allLocksFree());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T13：WBB 满 -> Stage2 冻结
//   关键时序：让 C 的 Stage1 与 B3 的 Stage2 同拍，
//   Stage1 看到 WBB 还有 3 个占用（接受），Stage2 看到 4 个（reserve 失败 -> 冻结）。
// -------------------------------------------------------------
static void test_wbb_full_stage2_freeze() {
    std::cout << "[T13] WBB 满 -> Stage2 冻结 ... ";

    Harness h;
    h.mem.rdLatency = 2;
    h.mem.wrLatency = 500;      // 写回长期挂起，保证 WBB 能满

    // set0：填满 4 路并全部写脏，保证 C 的 victim 一定是脏的
    const Addr D[4] = {
        lineAddr(0x10, 0), lineAddr(0x11, 0),
        lineAddr(0x12, 0), lineAddr(0x13, 0)
    };
    for (int i = 0; i < 4; ++i) {
        const size_t b = h.rdResps.size();
        h.submit(D[i], false, 0, static_cast<CpuId>(1 + i));
        assert(h.run_until([&] { return h.rdResps.size() > b; }));
    }
    for (int i = 0; i < 4; ++i) {
        const size_t b = h.wrResps.size();
        h.submit(D[i] + 4, true, 0xD000 + static_cast<Word>(i),
                 static_cast<CpuId>(5 + i));
        assert(h.run_until([&] { return h.wrResps.size() > b; }));
    }
    Line expD0 = h.mem.readLine(D[0]);
    expD0[1] = 0xD000;          // FIFO 会先淘汰 way0 = D0

    // set1：填满 4 路并全部写脏
    const Addr A[4] = {
        lineAddr(0x20, 1), lineAddr(0x21, 1),
        lineAddr(0x22, 1), lineAddr(0x23, 1)
    };
    for (int i = 0; i < 4; ++i) {
        const size_t b = h.rdResps.size();
        h.submit(A[i], false, 0, static_cast<CpuId>(9 + i));
        assert(h.run_until([&] { return h.rdResps.size() > b; }));
    }
    for (int i = 0; i < 4; ++i) {
        const size_t b = h.wrResps.size();
        h.submit(A[i] + 4, true, 0xA000 + static_cast<Word>(i),
                 static_cast<CpuId>(13 + i));
        assert(h.run_until([&] { return h.wrResps.size() > b; }));
    }

    // 背靠背发起 B0..B3（淘汰 set1 的 4 条脏行）和 C（set0 的脏 victim）
    const Addr B[4] = {
        lineAddr(0x30, 1), lineAddr(0x31, 1),
        lineAddr(0x32, 1), lineAddr(0x33, 1)
    };
    for (int i = 0; i < 4; ++i)
        h.submit(B[i], false, 0, static_cast<CpuId>(17 + i));
    const Addr C = lineAddr(0x40, 0);
    h.submit(C, false, 0, 21);

    bool sawFull = false, sawStuck = false;
    for (int i = 0; i < 200; ++i) {
        h.step();
        if (h.top.wbb().full()) sawFull = true;
        if (h.top.s2Stuck()) { sawStuck = true; break; }
    }
    assert(sawFull);
    assert(sawStuck);                       // C 在 Stage2 被冻结
    assert(h.top.wbb().full());

    // 解冻：让已挂起的写完成，并把新写的延迟降下来
    h.mem.wrLatency = 1;
    h.mem.drainWrites();

    // C 最终完成
    assert(h.run_until([&] {
        for (const auto& r : h.rdResps) if (r.id == 21) return true;
        return false;
    }, 400));

    // C 的数据正确
    for (const auto& r : h.rdResps)
        if (r.id == 21)
            assert(r.rData == h.mem.readLine(C)[decodeWordOff(C)]);

    // D0 的脏行写回数据正确
    assert(h.run_until([&] {
        for (const auto& w : h.mem.writes) if (w.first == D[0]) return true;
        return false;
    }, 400));
    for (const auto& w : h.mem.writes) {
        if (w.first == D[0]) {
            for (int o = 0; o < WORDS_PER_BLOCK; ++o) {
                if (w.second[o] != expD0[o]) {
                    std::cerr << "\n[WBB-full writeback mismatch] word=" << o
                              << " got=0x" << std::hex << w.second[o]
                              << " exp=0x" << expD0[o] << std::dec << "\n";
                    assert(false);
                }
            }
        }
    }

    h.run_cycles(20);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());
    assert(h.wbbEmpty());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T14：读响应队列满 -> Stage2 冻结
// -------------------------------------------------------------
static void test_readq_full_stage2_freeze() {
    std::cout << "[T14] 读响应队列满 -> Stage2 冻结 ... ";

    Harness h;
    const Addr A = 0x1000;
    const Line exp = h.mem.readLine(A);

    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));
    h.run_cycles(2);

    // 停止取走读响应
    h.top.cpuReadResp_ready = false;

    // 背靠背 5 条命中读
    for (int i = 0; i < 5; ++i)
        h.submit(A, false, 0, static_cast<CpuId>(2 + i));

    bool sawFull = false, sawStuck = false;
    for (int i = 0; i < 100; ++i) {
        h.step();
        if (h.top.readQueueSize() == RESP_QUEUE_DEPTH) sawFull = true;
        if (h.top.s2Stuck()) { sawStuck = true; break; }
    }
    assert(sawFull);
    assert(sawStuck);
    assert(h.top.readQueueSize() == RESP_QUEUE_DEPTH);
    assert(h.rdResps.size() == 1);       // 第 5 条还没返回

    // 解冻并收完
    h.top.cpuReadResp_ready = true;
    assert(h.run_until([&] { return h.rdResps.size() == 6; }, 300));
    for (const auto& r : h.rdResps)
        assert(r.rData == exp[decodeWordOff(A)]);

    h.run_cycles(5);
    assert(h.top.readQueueSize() == 0);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T15：写响应队列满 -> Stage2 冻结
// -------------------------------------------------------------
static void test_writeq_full_stage2_freeze() {
    std::cout << "[T15] 写响应队列满 -> Stage2 冻结 ... ";

    Harness h;
    const Addr A = 0x1000;

    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));
    h.run_cycles(2);

    // 停止取走写响应
    h.top.cpuWriteResp_ready = false;

    // 背靠背 5 条命中写
    for (int i = 0; i < 5; ++i)
        h.submit(A + 4, true, 0x1000 + static_cast<Word>(i),
                 static_cast<CpuId>(2 + i));

    bool sawFull = false, sawStuck = false;
    for (int i = 0; i < 100; ++i) {
        h.step();
        if (h.top.writeQueueSize() == RESP_QUEUE_DEPTH) sawFull = true;
        if (h.top.s2Stuck()) { sawStuck = true; break; }
    }
    assert(sawFull);
    assert(sawStuck);
    assert(h.top.writeQueueSize() == RESP_QUEUE_DEPTH);
    assert(h.wrResps.empty());

    // 解冻并收完
    h.top.cpuWriteResp_ready = true;
    assert(h.run_until([&] { return h.wrResps.size() == 5; }, 300));

    h.run_cycles(5);
    assert(h.top.writeQueueSize() == 0);

    // 最后一次写应生效
    const int set = decodeIndex(A);
    const int way = h.findWay(set, decodeTag(A));
    assert(way >= 0);
    assert(h.top.cache().getWord(set, way, 1) == 0x1004);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T16：RAW 旁路（读优先模式）
//   写 W 在 Stage2、读 R 在 Stage1 同沿同字；读优先下 R1 采到旧值，
//   必须靠 CacheTop 的 prevW1 旁路返回新值。
// -------------------------------------------------------------
static void test_raw_bypass() {
    std::cout << "[T16] RAW 旁路 / 读优先 ... ";

    Harness h;
    h.top.setCacheReadFirst(true);

    const Addr A = 0x1000;
    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));
    h.run_cycles(2);

    const Word W = 0xFEEDFACE;
    const size_t wb = h.wrResps.size();
    const size_t rb = h.rdResps.size();

    h.submit(A + 4, true, W, 2);      // 写命中
    h.submit(A + 4, false, 0, 3);     // 紧随其后的读

    assert(h.run_until([&] {
        return h.wrResps.size() > wb && h.rdResps.size() > rb;
    }, 200));

    assert(h.wrResps.back().id == 2);
    assert(h.rdResps.back().id == 3);
    assert(h.rdResps.back().rData == W);   // 旁路必须返回新值

    const int set = decodeIndex(A);
    const int way = h.findWay(set, decodeTag(A));
    assert(way >= 0);
    assert(h.top.cache().getWord(set, way, 1) == W);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T17：victim 假命中窗口（读优先模式）
//   A 在拍 N 淘汰 L；B 的 Stage1 在 N、Stage2 在 N+1。
//   B 的 R1 快照看到 L 仍然 valid，必须靠实时 !wayLocked 判 miss。
// -------------------------------------------------------------
static void test_victim_false_hit() {
    std::cout << "[T17] victim 假命中窗口 / 读优先 ... ";

    Harness h;
    h.top.setCacheReadFirst(true);
    h.mem.rdLatency = 2;

    const int set  = 0;
    const Addr L[4] = {
        lineAddr(0x10, set), lineAddr(0x11, set),
        lineAddr(0x12, set), lineAddr(0x13, set)
    };
    for (int i = 0; i < 4; ++i) {
        const size_t b = h.rdResps.size();
        h.submit(L[i], false, 0, static_cast<CpuId>(10 + i));
        assert(h.run_until([&] { return h.rdResps.size() > b; }));
    }
    assert(h.findWay(set, decodeTag(L[0])) == 0);   // L[0] 是 FIFO 最老

    const int readsBefore = h.mem.readCount(L[0]);

    // A：同 set 的新行，淘汰 L[0]；B：紧随其后访问 L[0]
    const Addr Y = lineAddr(0x50, set);
    h.submit(Y, false, 0, 20);
    h.submit(L[0], false, 0, 21);

    const size_t rb = h.rdResps.size();
    assert(h.run_until([&] { return h.rdResps.size() >= rb + 2; }, 200));

    // B 必须判 miss 并重新取 L[0]，而不是假命中旧行
    assert(h.mem.readCount(L[0]) == readsBefore + 1);

    const Line expL = h.mem.readLine(L[0]);
    for (const auto& r : h.rdResps)
        if (r.id == 21)
            assert(r.rData == expL[decodeWordOff(L[0])]);

    h.run_cycles(5);
    assert(h.mshrEmpty());
    assert(h.allLocksFree());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T18：MSHR 满时，"本会命中"的请求也被保守反压（§2.5 其三 / §7.14）
// -------------------------------------------------------------
static void test_mshr_full_would_hit_backpressure() {
    std::cout << "[T18] MSHR 满 / 命中请求被保守反压 ... ";

    Harness h;
    h.mem.rdLatency = 30;

    const Addr A = 0x1000;
    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() == 1; }));
    h.run_cycles(2);

    // 4 条不同 set 的 miss 占满 MSHR
    const Addr M[4] = { 0x1040, 0x1080, 0x10C0, 0x1100 };
    for (int i = 0; i < 4; ++i)
        h.submit(M[i], false, 0, static_cast<CpuId>(10 + i));
    assert(h.run_until([&] { return h.top.mshr().validEntries() == 4; }, 200));

    // 发一条本会命中 A 的读
    h.submit(A, false, 0, 20);

    bool sawBlocked = false;
    for (int i = 0; i < 10; ++i) {
        h.step();
        if (!h.top.cpu_ready) sawBlocked = true;
    }
    assert(sawBlocked);
    for (const auto& r : h.rdResps) assert(r.id != 20);   // 被挡住

    // MSHR 释放后该命中完成
    assert(h.run_until([&] {
        for (const auto& r : h.rdResps) if (r.id == 20) return true;
        return false;
    }, 400));

    // A 命中不额外读内存
    assert(h.mem.readCount(A) == 1);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T19：Slot 满导致合并冻结，释放后转为命中
// -------------------------------------------------------------
static void test_slot_full_merge_freeze(Harness& h) {
    std::cout << "[T19] Slot 满合并冻结 ... ";

    h.mem.rdLatency = 20;

    const Addr A = 0x3000;
    const Line exp = h.mem.readLine(A);

    // 背靠背 5 条同地址读：前 4 条填满 Slot，第 5 条 Stage2 冻结
    for (int i = 0; i < 5; ++i)
        h.submit(A, false, 0, static_cast<CpuId>(i + 1));

    bool sawStuck = false;
    for (int i = 0; i < 200; ++i) {
        h.step();
        if (h.top.s2Stuck() &&
            h.top.mshr().validEntries() == 1 &&
            h.top.mshr().entry(0).validCnt == MSHR_MAX_PENDING) {
            sawStuck = true;
            break;
        }
    }
    assert(sawStuck);

    assert(h.run_until([&] { return h.rdResps.size() == 5; }, 400));

    assert(h.mem.readCount(A) == 1);          // 合并 -> 只读一次
    for (int i = 0; i < 5; ++i) {
        assert(h.rdResps[i].id == static_cast<CpuId>(i + 1));
        assert(h.rdResps[i].rData == exp[decodeWordOff(A)]);
    }

    const int set = decodeIndex(A);
    const int way = h.findWay(set, decodeTag(A));
    assert(way >= 0);
    h.expectLine(set, way, decodeTag(A), exp, false);

    assert(h.mshrEmpty());
    assert(h.allLocksFree());

    std::cout << "ok\n";
}

// -------------------------------------------------------------
int main() {
    std::cout << "=== CacheTop full test ===\n";

    test_read_miss_full();
    test_write_hit_full();
    test_merge_full();
    test_write_allocate_merge();
    test_dirty_evict_full();
    test_clean_evict_full();
    test_hit_under_miss();
    test_mshr_full();
    test_wbb_same_addr();
    test_fifo_order();
    test_random_shadow();
    test_ooo_read_responses();
    test_wbb_full_stage2_freeze();
    test_readq_full_stage2_freeze();
    test_writeq_full_stage2_freeze();
    test_raw_bypass();
    test_victim_false_hit();
    test_mshr_full_would_hit_backpressure();

    // 最后一个用例保留 Harness，测试结束后打印最终 Cache 内容
    Harness finalH;
    test_slot_full_merge_freeze(finalH);

    std::cout << "\n=== final CacheMem dump (after all tests) ===\n";
    finalH.top.cache().dump(std::cout);

    std::cout << "=== all CacheTop full tests passed ===\n";
    return 0;
}
