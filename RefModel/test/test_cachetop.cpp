// test_cachetop.cpp
// =============================================================
// CacheTop 集成测试
//
// 用一个简单的行为级内存模型驱动 CacheTop，覆盖：
//   T1 读未命中：Stage1/Stage2 -> MSHR -> 填充 -> 重放 -> 读响应
//   T2 写命中 + 读回：W1 写入、写响应、后续读命中
//   T3 同地址合并：两条同线请求合并进一个 MSHR 条目，按序返回
//   T4 脏行淘汰：替换脏行 -> WBB 预留 -> push -> 内存写回
//
// 编译（在 RefModel 目录下）：
//   make run-cachetop
// =============================================================

#include "CacheTop.hpp"

#include <cassert>
#include <cstdint>
#include <deque>
#include <iostream>
#include <map>
#include <vector>

using namespace dcache;

// -------------------------------------------------------------
// 简单行为级内存
//   - 读/写延迟固定
//   - 未写过的行返回确定性数据
// -------------------------------------------------------------
struct SimpleMem {
    std::map<Addr, Line> mem;
    std::vector<std::pair<Addr, Line>> writes;

    int rdLatency = 2;
    int wrLatency = 2;

    struct RdPend { int remain; Addr addr; BusId id; };
    struct WrPend { int remain; BusId id; };
    std::deque<RdPend> rdPend;
    std::deque<WrPend> wrPend;

    bool  rdRespValid = false;
    Line  rdRespLine{};
    BusId rdRespId = 0;

    bool  wrRespValid = false;
    BusId wrRespId = 0;

    Line readLine(Addr a) const {
        auto it = mem.find(a);
        if (it != mem.end()) return it->second;
        Line l{};
        for (int i = 0; i < WORDS_PER_BLOCK; ++i)
            l[i] = static_cast<Word>(a) + static_cast<Word>(i);
        return l;
    }

    void tick(bool rdV, Addr rdA, BusId rdId, bool rdR,
              bool wrV, Addr wrA, const Line& wrL, BusId wrId, bool wrR) {
        rdRespValid = false;
        wrRespValid = false;

        // 先推进已有事务
        if (!rdPend.empty()) {
            if (--rdPend.front().remain <= 0) {
                rdRespValid = true;
                rdRespLine = readLine(rdPend.front().addr);
                rdRespId   = rdPend.front().id;
                rdPend.pop_front();
            }
        }
        if (!wrPend.empty()) {
            if (--wrPend.front().remain <= 0) {
                wrRespValid = true;
                wrRespId   = wrPend.front().id;
                wrPend.pop_front();
            }
        }

        // 再接收新事务
        if (rdV && rdR)
            rdPend.push_back(RdPend{ rdLatency, rdA, rdId });
        if (wrV && wrR) {
            mem[wrA] = wrL;
            writes.push_back({ wrA, wrL });
            wrPend.push_back(WrPend{ wrLatency, wrId });
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
        assert(id < CPU_ID_LIMIT && "CPU ID 超出 ID_WIDTH 范围");
        reqs.push_back(CpuReq{ a, wr, wd, id });
    }

    void step() {
        // 驱动下一条 CPU 请求
        if (!reqs.empty()) {
            top.cpu_valid = true;
            top.cpu_addr  = reqs.front().addr;
            top.cpu_wrEn  = reqs.front().wr;
            top.cpu_wData = reqs.front().wData;
            top.cpu_id    = reqs.front().id;
        } else {
            top.cpu_valid = false;
        }

        // 组合：得到 cpu_ready / 内存请求
        top.eval();
        const bool accepted = top.cpu_valid && top.cpu_ready;

        // 内存推进
        mem.tick(top.memReadReq_valid, top.memReadReq_addr, top.memReadReq_id,
                 top.memReadReq_ready,
                 top.memWriteReq_valid, top.memWriteReq_addr,
                 top.memWriteReq_line, top.memWriteReq_id,
                 top.memWriteReq_ready);

        // 把内存响应接回 CacheTop
        top.memReadResp_valid = mem.rdRespValid;
        top.memReadResp_line  = mem.rdRespLine;
        top.memReadResp_id    = mem.rdRespId;
        top.memWriteResp_valid = mem.wrRespValid;
        top.memWriteResp_id    = mem.wrRespId;

        // 时钟沿
        top.tick();

        // 记录本拍被取走的响应（tick 内部的 eval 已算出本拍 valid）
        if (top.cpuReadResp_valid  && top.cpuReadResp_ready)
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
};

// -------------------------------------------------------------
// T1：读未命中
// -------------------------------------------------------------
static void test_read_miss() {
    std::cout << "[T1] 读未命中 ... ";

    Harness h;
    const Addr A = 0x1000;
    const Line expect = h.mem.readLine(A);

    h.submit(A, false, 0, 1);
    const bool ok = h.run_until([&] { return h.rdResps.size() >= 1; });
    assert(ok);
    assert(h.rdResps[0].id == 1);
    assert(h.rdResps[0].rData == expect[0]);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T2：写命中 + 读回
// -------------------------------------------------------------
static void test_write_hit() {
    std::cout << "[T2] 写命中 + 读回 ... ";

    Harness h;
    const Addr A = 0x1000;

    // 先读一次，把行填进来
    h.submit(A, false, 0, 1);
    assert(h.run_until([&] { return h.rdResps.size() >= 1; }));

    // 写命中（A + 4 -> wordOff 1）
    const Word WDATA = 0xDEADBEEF;
    h.submit(A + 4, true, WDATA, 2);
    assert(h.run_until([&] { return h.wrResps.size() >= 1; }));
    assert(h.wrResps[0].id == 2);

    // 再读回
    h.submit(A + 4, false, 0, 3);
    assert(h.run_until([&] { return h.rdResps.size() >= 2; }));
    assert(h.rdResps[1].id == 3);
    assert(h.rdResps[1].rData == WDATA);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T3：同地址合并
// -------------------------------------------------------------
static void test_merge() {
    std::cout << "[T3] 同地址合并 ... ";

    Harness h;
    const Addr A = 0x2000;
    const Line expect = h.mem.readLine(A);

    // 背靠背两条同线读；第二条应合并进第一条的 MSHR 条目
    h.submit(A, false, 0, 1);
    h.submit(A, false, 0, 2);

    assert(h.run_until([&] { return h.rdResps.size() >= 2; }));
    assert(h.rdResps[0].id == 1);
    assert(h.rdResps[1].id == 2);
    assert(h.rdResps[0].rData == expect[0]);
    assert(h.rdResps[1].rData == expect[0]);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T4：脏行淘汰 -> WBB 写回
// -------------------------------------------------------------
static void test_dirty_evict(Harness& h) {
    std::cout << "[T4] 脏行淘汰 / WBB 写回 ... ";

    // 先把 set0 的 4 条路填满
    const Addr addrs[4] = { 0x1000, 0x2000, 0x3000, 0x4000 };
    for (int i = 0; i < 4; ++i) {
        const size_t before = h.rdResps.size();
        h.submit(addrs[i], false, 0, static_cast<CpuId>(10 + i));
        assert(h.run_until([&] { return h.rdResps.size() > before; }));
    }

    // 把 0x1000 写脏（FIFO 中它是最老的）
    const Word W = 0xCAFEBABE;
    Line expOld = h.mem.readLine(0x1000);
    expOld[1] = W;
    h.submit(0x1000 + 4, true, W, 20);
    assert(h.run_until([&] { return h.wrResps.size() >= 1; }));

    // 第 5 条 miss -> 淘汰 way0（0x1000，脏）
    const size_t rdBefore = h.rdResps.size();
    h.submit(0x5000, false, 0, 30);
    assert(h.run_until([&] { return h.rdResps.size() > rdBefore; }));

    // 等 WBB 把脏行写回内存
    assert(h.run_until([&] { return !h.mem.writes.empty(); }, 200));
    assert(h.mem.writes[0].first == 0x1000);
    // 写回整行数据（含写脏的字）
    for (int o = 0; o < WORDS_PER_BLOCK; ++o)
        assert(h.mem.writes[0].second[o] == expOld[o]);

    // 新行正确填入，旧行失效
    const int  set    = decodeIndex(0x5000);
    const Tag  newTag = decodeTag(0x5000);
    const Tag  oldTag = decodeTag(0x1000);
    int newWay = -1, oldWay = -1;
    for (int w = 0; w < NUM_WAYS; ++w) {
        if (!h.top.cache().getValid(set, w)) continue;
        if (h.top.cache().getTag(set, w) == newTag) newWay = w;
        if (h.top.cache().getTag(set, w) == oldTag) oldWay = w;
    }
    assert(newWay >= 0);
    assert(oldWay == -1);
    const Line expNew = h.mem.readLine(0x5000);
    for (int o = 0; o < WORDS_PER_BLOCK; ++o)
        assert(h.top.cache().getWord(set, newWay, o) == expNew[o]);
    assert(!h.top.cache().getDirty(set, newWay));   // 纯读 miss

    std::cout << "ok\n";
}

// -------------------------------------------------------------
int main() {
    std::cout << "=== CacheTop integration test ===\n";

    test_read_miss();
    test_write_hit();
    test_merge();

    Harness finalH;
    test_dirty_evict(finalH);

    std::cout << "\n=== final CacheMem dump (after all tests) ===\n";
    finalH.top.cache().dump(std::cout);

    std::cout << "=== all CacheTop tests passed ===\n";
    return 0;
}
