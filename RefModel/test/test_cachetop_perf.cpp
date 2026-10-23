// test_cachetop_perf.cpp
// =============================================================
// CacheTop 局部性性能测试
//
// 设计目标：把"时间局部性"和"空间局部性"作为受控变量，而不是只做
// 顺序流 / 纯随机 / 容量扫描。
//
// 工作负载（模式 A）：
//   - 地址空间：1024 个 Cache 行，即 64KB（Cache 容量 8KB，工作集是 8 倍）
//   - 总指令数：1024 * 50 = 51,200 条 L/S
//   - 每 100 条为一个 block：
//       * 偶数 block：下一条有 60% 概率与上一条"同地址"；
//         否则在 1024 行 × 16 字中随机选一个不同地址。
//       * 奇数 block：下一条 0% 同地址，总是随机选一个不同地址。
//       * 每 100 条切换一次，循环。
//   - 每个 block 的第一条为新的随机地址（边界处不延续上一条）。
//   - L/S 比例 50/50，store 数据随机。
//   - 地址 = line * 64 + wordOff * 4，字对齐。
//
// 统计拆分：
//   1) 整体：命中率 / 吞吐 / 延迟 / MSHR / WBB / Stall。
//   2) 阶段：60% 同地址阶段 vs 0% 随机阶段。
//   3) 局部性类别：
//        - same address            同地址（时间局部性）
//        - same line, diff word    同行不同字（空间局部性）
//        - different line          不同行（无局部性）
//   4) 阶段 × 类别矩阵。
//
// 正确性：每次读响应都与按程序顺序维护的影子内存比对。
//
// 编译：
//   make run-perf
// =============================================================

#include "CacheTop.hpp"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <iostream>
#include <map>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>

using namespace dcache;

// -------------------------------------------------------------
// 确定性初始行（与功能测试口径一致）
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
    const Addr base = a & ~OFFSET_MASK;
    return makeInitialLine(base)[decodeWordOff(a)];
}

// -------------------------------------------------------------
// 行为级内存：读/写固定延迟，每拍每通道最多一个响应
// -------------------------------------------------------------
struct SimpleMem {
    std::map<Addr, Line> mem;
    int rdLatency = 8;
    int wrLatency = 8;

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

    void tick(bool rdV, Addr rdA, BusId rdId, bool rdR,
              bool wrV, Addr wrA, const Line& wrL, BusId wrId, bool wrR) {
        rdRespValid = false;
        wrRespValid = false;

        // 推进已在途读（每拍最多返回一个）
        for (int i = 0; i < static_cast<int>(rdPend.size()); ++i) {
            if (--rdPend[i].remain <= 0) {
                rdRespValid = true;
                rdRespLine  = readLine(rdPend[i].addr);
                rdRespId    = rdPend[i].id;
                rdPend.erase(rdPend.begin() + i);
                break;
            }
        }

        // 推进已在途写（每拍最多返回一个）
        for (int i = 0; i < static_cast<int>(wrPend.size()); ++i) {
            if (--wrPend[i].remain <= 0) {
                mem[wrPend[i].addr] = wrPend[i].line;
                wrRespValid = true;
                wrRespId    = wrPend[i].id;
                wrPend.erase(wrPend.begin() + i);
                break;
            }
        }

        // 接收新事务
        if (rdV && rdR) rdPend.push_back(RdPend{ rdLatency, rdA, rdId });
        if (wrV && wrR) wrPend.push_back(WrPend{ wrLatency, wrA, wrL, wrId });
    }
};

// -------------------------------------------------------------
// 局部性类别
// -------------------------------------------------------------
enum LocalityClass {
    LOC_SAME_ADDR       = 0,   // 同地址（时间局部性）
    LOC_SAME_LINE_WORD  = 1,   // 同行不同字（空间局部性）
    LOC_DIFF_LINE       = 2,   // 不同行（无局部性）
    LOC_CLASSES         = 3
};

struct ReqSpec {
    Addr addr;
    bool wr;
    Word data;
    int  phase;      // 0 = 60% block, 1 = 0% block
    int  locality;   // LocalityClass
};

// CPU 请求（ID 在"被 Cache 接收"时从 freeIds_ 池中分配）
struct CpuReq {
    Addr  addr;
    bool  wr;
    Word  data;
    int   phase;
    int   locality;
};

// -------------------------------------------------------------
// 分类统计
// -------------------------------------------------------------
struct ClassStats {
    uint64_t reqs   = 0;
    uint64_t hits   = 0;   // Cache 命中
    uint64_t merges = 0;   // MSHR 合并

    uint64_t reads       = 0, readHits  = 0, readMerges  = 0;
    uint64_t writes      = 0, writeHits = 0, writeMerges = 0;

    std::vector<uint64_t> service;

    double cacheHitRate() const {
        return reqs ? static_cast<double>(hits) / reqs : 0.0;
    }
    double effHitRate() const {
        return reqs ? static_cast<double>(hits + merges) / reqs : 0.0;
    }
    double readHitRate() const {
        return reads ? static_cast<double>(readHits) / reads : 0.0;
    }
    double writeHitRate() const {
        return writes ? static_cast<double>(writeHits) / writes : 0.0;
    }
};

// -------------------------------------------------------------
// 整体阶段报告
// -------------------------------------------------------------
struct PhaseReport {
    uint64_t requests = 0;
    uint64_t reads = 0;
    uint64_t writes = 0;
    uint64_t lastResp = 0;
    uint64_t cycles = 0;
    bool timedOut = false;

    CacheTop::PerfCounters perf{};

    double   mshrAvg = 0, wbbAvg = 0, lockAvg = 0, rdQAvg = 0, wrQAvg = 0;
    uint64_t mshrMax = 0, wbbMax = 0, lockMax = 0;

    std::vector<uint64_t> readService, readWait;
    std::vector<uint64_t> writeService, writeWait;

    ClassStats phase[2];               // 0 = 60%, 1 = 0%
    ClassStats loc[LOC_CLASSES];       // same addr / same line / diff line
    ClassStats phaseLoc[2][LOC_CLASSES];

    double throughput() const {
        return lastResp ? static_cast<double>(requests) / lastResp : 0.0;
    }
    double throughputQuiesce() const {
        return cycles ? static_cast<double>(requests) / cycles : 0.0;
    }
    double readHitRate() const {
        return reads ? static_cast<double>(perf.readHits) / reads : 0.0;
    }
    double readEffRate() const {
        return reads ? static_cast<double>(perf.readHits + perf.readMerges) / reads : 0.0;
    }
    double writeHitRate() const {
        return writes ? static_cast<double>(perf.writeHits) / writes : 0.0;
    }
    double writeEffRate() const {
        return writes ? static_cast<double>(perf.writeHits + perf.writeMerges) / writes : 0.0;
    }
};

static CacheTop::PerfCounters diffPerf(const CacheTop::PerfCounters& a,
                                       const CacheTop::PerfCounters& b) {
    CacheTop::PerfCounters d;
#define D(f) d.f = b.f - a.f
    D(s1Accepted); D(cpuReads); D(cpuWrites);
    D(readHits); D(writeHits); D(hitUnderMiss);
    D(mshrAllocs); D(mshrMerges); D(readMerges); D(writeMerges);
    D(evictions); D(dirtyEvictions); D(writebacks);
    D(memReads); D(memWrites);
    D(cpuStallCycles); D(s2StallCycles);
    D(stallRespFull); D(stallWbbFull); D(stallMshrFull);
    D(stallNoWay); D(stallMergeBlocked); D(stallWbSame);
#undef D
    return d;
}

// -------------------------------------------------------------
// Harness
// -------------------------------------------------------------
struct Harness {
    CacheTop top;
    SimpleMem mem;

    std::deque<CpuReq> reqs;
    uint64_t headReadyCycle = 0;

    // §3.4：CPU ID 只有 ID_WIDTH 位，激励不得越界。
    // 这里用一个小池子：请求被接收时分配、响应返回时归还。
    // 在途请求上界 = 16(MSHR) + 1(Stage2) + 8(响应队列) = 25 < CPU_ID_LIMIT，
    // 因此池子永远不会空（空了就说明设计或激励违反了 §3.4）。
    std::deque<CpuId> freeIds_;

    std::unordered_map<CpuId, Word>     expectedRead;
    std::unordered_map<CpuId, uint64_t> acceptCycle, readyCycle;
    std::unordered_map<CpuId, int>      phaseOf, locOf;
    std::map<Addr, Word> shadow;

    uint64_t cycles = 0;
    uint64_t rdCount = 0, wrCount = 0;
    uint64_t respBase = 0;
    uint64_t phaseExpected = 0;
    uint64_t phaseStart = 0;
    uint64_t accepted = 0;

    bool measuring = false;
    bool lastRespSet = false;
    uint64_t lastRespCycle = 0;
    bool timedOut = false;

    uint64_t mshrSum = 0, wbbSum = 0, lockSum = 0, rdQSum = 0, wrQSum = 0, samples = 0;
    uint64_t maxMshr = 0, maxWbb = 0, maxLock = 0;

    std::vector<uint64_t> readService, readWait;
    std::vector<uint64_t> writeService, writeWait;

    ClassStats phaseStats[2];
    ClassStats locStats[LOC_CLASSES];
    ClassStats phaseLocStats[2][LOC_CLASSES];

    CacheTop::PerfCounters perfBefore{};

    Harness(int rdLat = 8, int wrLat = 8) {
        mem.rdLatency = rdLat;
        mem.wrLatency = wrLat;
        top.memReadReq_ready   = true;
        top.memWriteReq_ready  = true;
        top.cpuReadResp_ready  = true;
        top.cpuWriteResp_ready = true;
        for (CpuId i = 0; i < CPU_ID_LIMIT; ++i) freeIds_.push_back(i);
    }

    // ---------- 提交 ----------
    void submitBatch(const std::vector<ReqSpec>& specs) {
        for (const auto& s : specs)
            reqs.push_back(CpuReq{ s.addr, s.wr, s.data, s.phase, s.locality });
    }

    // ---------- 观测辅助 ----------
    bool mshrEmpty() const { return top.mshr().validEntries() == 0; }

    bool wbbEmpty() const {
        for (int i = 0; i < WBB_ENTRIES; ++i)
            if (top.wbb().getValid(i) || top.wbb().getReserved(i) || top.wbb().getIssued(i))
                return false;
        return true;
    }

    bool allLocksFree() const {
        for (int s = 0; s < NUM_SETS; ++s)
            for (int w = 0; w < NUM_WAYS; ++w)
                if (top.locked(s, w)) return false;
        return true;
    }

    // ---------- 分类计数 ----------
    static void addClass(ClassStats& s, bool isWrite, bool hit, bool merged,
                         uint64_t lat) {
        ++s.reqs;
        s.hits   += hit    ? 1 : 0;
        s.merges += merged ? 1 : 0;

        if (isWrite) {
            ++s.writes;
            s.writeHits   += hit    ? 1 : 0;
            s.writeMerges += merged ? 1 : 0;
        } else {
            ++s.reads;
            s.readHits   += hit    ? 1 : 0;
            s.readMerges += merged ? 1 : 0;
        }
        s.service.push_back(lat);
    }

    // ---------- 单拍 ----------
    void step() {
        // 1) 布置 CPU 请求（ID 在接收时分配，这里先呈现池首）
        if (!reqs.empty()) {
            top.cpu_valid = true;
            top.cpu_addr  = reqs.front().addr;
            top.cpu_wrEn  = reqs.front().wr;
            top.cpu_wData = reqs.front().data;
            top.cpu_id    = freeIds_.empty() ? 0 : freeIds_.front();
        } else {
            top.cpu_valid = false;
        }

        top.eval();
        const bool acceptedNow = top.cpu_valid && top.cpu_ready;

        // 2) 内存
        mem.tick(top.memReadReq_valid, top.memReadReq_addr, top.memReadReq_id,
                 top.memReadReq_ready,
                 top.memWriteReq_valid, top.memWriteReq_addr,
                 top.memWriteReq_line, top.memWriteReq_id,
                 top.memWriteReq_ready);

        top.memReadResp_valid  = mem.rdRespValid;
        top.memReadResp_line   = mem.rdRespLine;
        top.memReadResp_id     = mem.rdRespId;
        top.memWriteResp_valid = mem.wrRespValid;
        top.memWriteResp_id    = mem.wrRespId;

        top.tick();

        // 3) 读响应
        if (top.cpuReadResp_ready && top.cpuReadResp_valid) {
            const CpuId id   = top.cpuReadResp_id;
            const Word  data = top.cpuReadResp_rData;

            auto e = expectedRead.find(id);
            if (e == expectedRead.end()) {
                std::cerr << "\n[perf] unexpected read response id=" << id << "\n";
                assert(false);
            }
            if (data != e->second) {
                std::cerr << "\n[perf] read data mismatch id=" << id
                          << " got=0x" << std::hex << data
                          << " exp=0x" << e->second << std::dec << "\n";
                assert(false);
            }
            expectedRead.erase(e);

            auto a = acceptCycle.find(id);
            if (a == acceptCycle.end()) {
                std::cerr << "\n[perf] read response without accept id=" << id << "\n";
                assert(false);
            }
            const uint64_t lat = cycles - a->second;

            if (measuring) {
                readService.push_back(lat);
                readWait.push_back(cycles - readyCycle.at(id));
            }

            const int ph = phaseOf.at(id);
            const int lc = locOf.at(id);
            const bool hit    = top.cpuReadResp_hit;
            const bool merged = top.cpuReadResp_merged;

            addClass(phaseStats[ph],       false, hit, merged, lat);
            addClass(locStats[lc],         false, hit, merged, lat);
            addClass(phaseLocStats[ph][lc], false, hit, merged, lat);

            acceptCycle.erase(a);
            readyCycle.erase(id);
            phaseOf.erase(id);
            locOf.erase(id);
            freeIds_.push_back(id);   // 响应已返回，ID 可安全复用
            ++rdCount;
        }

        // 4) 写响应
        if (top.cpuWriteResp_ready && top.cpuWriteResp_valid) {
            const CpuId id = top.cpuWriteResp_id;

            auto a = acceptCycle.find(id);
            if (a == acceptCycle.end()) {
                std::cerr << "\n[perf] write response without accept id=" << id << "\n";
                assert(false);
            }
            const uint64_t lat = cycles - a->second;

            if (measuring) {
                writeService.push_back(lat);
                writeWait.push_back(cycles - readyCycle.at(id));
            }

            const int ph = phaseOf.at(id);
            const int lc = locOf.at(id);
            const bool hit    = top.cpuWriteResp_hit;
            const bool merged = top.cpuWriteResp_merged;

            addClass(phaseStats[ph],       true, hit, merged, lat);
            addClass(locStats[lc],         true, hit, merged, lat);
            addClass(phaseLocStats[ph][lc], true, hit, merged, lat);

            acceptCycle.erase(a);
            readyCycle.erase(id);
            phaseOf.erase(id);
            locOf.erase(id);
            freeIds_.push_back(id);   // 响应已返回，ID 可安全复用
            ++wrCount;
        }

        // 5) 接收：分配 ID，记录延迟起点、影子值、阶段/局部性
        if (acceptedNow) {
            const CpuReq& r = reqs.front();
            assert(!freeIds_.empty() && "CPU ID 池耗尽：在途请求超过 CPU_ID_LIMIT");
            const CpuId id = freeIds_.front();
            freeIds_.pop_front();

            acceptCycle[id] = cycles;
            readyCycle[id]  = headReadyCycle;
            phaseOf[id]     = r.phase;
            locOf[id]       = r.locality;

            if (r.wr) {
                shadow[r.addr] = r.data;
            } else {
                auto it = shadow.find(r.addr);
                expectedRead[id] = (it != shadow.end()) ? it->second
                                                       : initialWord(r.addr);
            }

            reqs.pop_front();
            headReadyCycle = cycles + 1;
            ++accepted;
        }

        // 6) 占用采样（沿后状态）
        const int mshrOcc = top.mshr().validEntries();
        int wbbOcc = 0;
        for (int i = 0; i < WBB_ENTRIES; ++i)
            if (top.wbb().getValid(i) || top.wbb().getReserved(i) || top.wbb().getIssued(i))
                ++wbbOcc;
        int lockOcc = 0;
        for (int s = 0; s < NUM_SETS; ++s)
            for (int w = 0; w < NUM_WAYS; ++w)
                if (top.locked(s, w)) ++lockOcc;

        mshrSum += mshrOcc;
        wbbSum  += wbbOcc;
        lockSum += lockOcc;
        rdQSum  += top.readQueueSize();
        wrQSum  += top.writeQueueSize();
        ++samples;
        maxMshr = std::max<uint64_t>(maxMshr, mshrOcc);
        maxWbb  = std::max<uint64_t>(maxWbb,  wbbOcc);
        maxLock = std::max<uint64_t>(maxLock, lockOcc);

        // 7) 最后一个 CPU 响应
        if (measuring && !lastRespSet &&
            (rdCount + wrCount - respBase) >= phaseExpected) {
            lastRespCycle = cycles;
            lastRespSet   = true;
        }

        ++cycles;
    }

    // ---------- 阶段控制 ----------
    void beginMeasure() {
        assert(expectedRead.empty());
        assert(acceptCycle.empty());
        assert(readyCycle.empty());
        assert(phaseOf.empty());
        assert(locOf.empty());
        assert(freeIds_.size() == CPU_ID_LIMIT);   // 上一阶段已排空，ID 全部归还

        measuring     = true;
        phaseStart    = cycles;
        respBase      = rdCount + wrCount;
        phaseExpected = 0;
        accepted      = 0;
        lastRespSet   = false;
        lastRespCycle = 0;
        timedOut      = false;

        perfBefore = top.perf();

        readService.clear(); readWait.clear();
        writeService.clear(); writeWait.clear();

        for (auto& s : phaseStats) s = ClassStats{};
        for (auto& s : locStats)   s = ClassStats{};
        for (auto& row : phaseLocStats)
            for (auto& s : row) s = ClassStats{};

        mshrSum = wbbSum = lockSum = rdQSum = wrQSum = 0;
        samples = 0;
        maxMshr = maxWbb = maxLock = 0;
    }

    void runToTarget(uint64_t target) {
        const uint64_t maxCycles = 2000000;
        while ((rdCount + wrCount) < target && (cycles - phaseStart) < maxCycles)
            step();

        timedOut = ((rdCount + wrCount) < target);
        if (!lastRespSet) lastRespCycle = cycles;

        // 等 MSHR / WBB / WayLock 全部排空，统计写回尾巴
        const uint64_t drainStart = cycles;
        while (!(mshrEmpty() && wbbEmpty() && allLocksFree()) &&
               (cycles - drainStart) < 200000)
            step();

        if (!timedOut) {
            assert(accepted == phaseExpected);
            assert(expectedRead.empty());
            assert(acceptCycle.empty());
            assert(readyCycle.empty());
            assert(phaseOf.empty());
            assert(locOf.empty());
        }
    }

    void runBatch(const std::vector<ReqSpec>& specs) {
        beginMeasure();
        submitBatch(specs);
        headReadyCycle = phaseStart;
        phaseExpected  = specs.size();
        runToTarget(respBase + phaseExpected);
    }

    PhaseReport report(const std::string& /*name*/) const {
        PhaseReport r;
        r.requests = phaseExpected;
        r.perf     = diffPerf(perfBefore, top.perf());
        r.reads    = r.perf.cpuReads;
        r.writes   = r.perf.cpuWrites;
        r.lastResp = (lastRespCycle >= phaseStart) ? (lastRespCycle - phaseStart) : 0;
        r.cycles   = cycles - phaseStart;
        r.timedOut = timedOut;

        r.mshrAvg = samples ? static_cast<double>(mshrSum) / samples : 0.0;
        r.wbbAvg  = samples ? static_cast<double>(wbbSum)  / samples : 0.0;
        r.lockAvg = samples ? static_cast<double>(lockSum) / samples : 0.0;
        r.rdQAvg  = samples ? static_cast<double>(rdQSum)  / samples : 0.0;
        r.wrQAvg  = samples ? static_cast<double>(wrQSum)  / samples : 0.0;
        r.mshrMax = maxMshr;
        r.wbbMax  = maxWbb;
        r.lockMax = maxLock;

        r.readService  = readService;
        r.readWait     = readWait;
        r.writeService = writeService;
        r.writeWait    = writeWait;

        for (int p = 0; p < 2; ++p) r.phase[p] = phaseStats[p];
        for (int l = 0; l < LOC_CLASSES; ++l) r.loc[l] = locStats[l];
        for (int p = 0; p < 2; ++p)
            for (int l = 0; l < LOC_CLASSES; ++l)
                r.phaseLoc[p][l] = phaseLocStats[p][l];

        return r;
    }
};

// -------------------------------------------------------------
// 统计小工具
// -------------------------------------------------------------
static double avgOf(const std::vector<uint64_t>& v) {
    if (v.empty()) return 0.0;
    uint64_t s = 0;
    for (auto x : v) s += x;
    return static_cast<double>(s) / v.size();
}

static uint64_t pctOf(const std::vector<uint64_t>& v, double p) {
    if (v.empty()) return 0;
    std::vector<uint64_t> s = v;
    std::sort(s.begin(), s.end());
    const size_t i = static_cast<size_t>(p * (s.size() - 1));
    return s[i];
}

static uint64_t maxOf(const std::vector<uint64_t>& v) {
    return v.empty() ? 0 : *std::max_element(v.begin(), v.end());
}

// -------------------------------------------------------------
// 地址 / 数据生成
// -------------------------------------------------------------
static Addr makeLineAddr(int line, int word) {
    return static_cast<Addr>(line) * BLOCK_SIZE +
           static_cast<Addr>(word) * BYTE_WIDTH;
}

struct LocalityWorkload {
    std::vector<ReqSpec> reqs;
    uint64_t phaseReqs[2] = { 0, 0 };
    uint64_t sameAddr = 0;
    uint64_t sameLine = 0;
    uint64_t diffLine = 0;

    uint64_t total() const { return reqs.size(); }
};

// 1024 个 Cache 行（64KB），总 n 条指令。
// phase 0（60% 同地址）与 phase 1（0% 同地址）每 100 条交替。
static LocalityWorkload genLocalityBurst(uint64_t n, uint32_t seed) {
    LocalityWorkload wl;
    wl.reqs.reserve(n);

    std::mt19937 rng(seed);
    std::mt19937 dataRng(seed ^ 0xA5A5A5A5u);   // 独立随机源，避免扰动地址序列
    std::uniform_int_distribution<int> lineDist(1, 1024);
    std::uniform_int_distribution<int> wordDist(0, WORDS_PER_BLOCK - 1);
    std::uniform_int_distribution<int> coin(0, 99);
    std::uniform_int_distribution<int> ls(0, 1);

    Addr prevAddr = 0;
    bool havePrev = false;

    for (uint64_t i = 0; i < n; ++i) {
        const int  phase      = static_cast<int>((i / 100) % 2);  // 0=60%, 1=0%
        const bool blockStart = (i % 100 == 0);

        Addr addr;
        if (!havePrev || blockStart) {
            // 每个 block 的第一条：新的随机地址
            do {
                addr = makeLineAddr(lineDist(rng), wordDist(rng));
            } while (havePrev && addr == prevAddr);
        } else if (phase == 0 && coin(rng) < 60) {
            // 60% 同地址（时间局部性）
            addr = prevAddr;
        } else {
            // 40% / 0% 阶段：随机但强制不同于上一条
            do {
                addr = makeLineAddr(lineDist(rng), wordDist(rng));
            } while (addr == prevAddr);
        }

        // 分类
        int cls;
        if (!havePrev) {
            cls = LOC_DIFF_LINE;
        } else if (addr == prevAddr) {
            cls = LOC_SAME_ADDR;
        } else if ((addr & ~OFFSET_MASK) == (prevAddr & ~OFFSET_MASK)) {
            cls = LOC_SAME_LINE_WORD;
        } else {
            cls = LOC_DIFF_LINE;
        }

        const bool wr = (ls(rng) == 1);   // 50/50 L/S
        const Word data = static_cast<Word>(dataRng());   // store 数据随机

        wl.reqs.push_back(ReqSpec{ addr, wr, data, phase, cls });
        ++wl.phaseReqs[phase];
        if (cls == LOC_SAME_ADDR)      ++wl.sameAddr;
        else if (cls == LOC_SAME_LINE_WORD) ++wl.sameLine;
        else                           ++wl.diffLine;

        prevAddr = addr;
        havePrev = true;
    }

    return wl;
}

// -------------------------------------------------------------
// 打印
// -------------------------------------------------------------
static void printReport(const PhaseReport& r) {
    std::cout << "\n--- overall ---\n";
    std::cout << " requests  : " << r.requests
              << " (R=" << r.reads << " W=" << r.writes << ")\n";
    std::cout << " cycles    : lastResp=" << r.lastResp
              << " quiesce=" << r.cycles
              << " (tail=" << (r.cycles - r.lastResp) << ")\n";

    std::cout << std::fixed << std::setprecision(3);
    std::cout << " throughput: " << r.throughput() << " req/cyc (last resp), "
              << r.throughputQuiesce() << " req/cyc (quiesce)\n";

    std::cout << std::setprecision(1);
    std::cout << " hit rate  :";
    if (r.reads)
        std::cout << " read " << r.readHitRate() * 100.0 << "%"
                  << " (effective " << r.readEffRate() * 100.0 << "%)";
    if (r.writes)
        std::cout << "  write " << r.writeHitRate() * 100.0 << "%"
                  << " (effective " << r.writeEffRate() * 100.0 << "%)";
    std::cout << "\n";

    std::cout << " MSHR      : allocs=" << r.perf.mshrAllocs
              << " merges=" << r.perf.mshrMerges
              << " (R=" << r.perf.readMerges << " W=" << r.perf.writeMerges << ")"
              << " avg=" << std::setprecision(2) << r.mshrAvg
              << " max=" << r.mshrMax
              << " hit-under-miss=" << r.perf.hitUnderMiss << "\n";

    std::cout << " WBB       : writebacks=" << r.perf.writebacks
              << " evictions=" << r.perf.evictions
              << " dirtyEvict=" << r.perf.dirtyEvictions
              << " avg=" << r.wbbAvg << " max=" << r.wbbMax << "\n";

    const uint64_t bytes = (r.perf.memReads + r.perf.memWrites) * BLOCK_SIZE;
    std::cout << " memory    : reads=" << r.perf.memReads
              << " writes=" << r.perf.memWrites
              << " bytes=" << bytes
              << " B/cyc=" << (r.lastResp ? static_cast<double>(bytes) / r.lastResp : 0.0)
              << "\n";

    std::cout << " stalls    : cpu=" << r.perf.cpuStallCycles
              << " s2=" << r.perf.s2StallCycles
              << " [respFull=" << r.perf.stallRespFull
              << " wbbFull=" << r.perf.stallWbbFull
              << " mshrFull=" << r.perf.stallMshrFull
              << " noWay=" << r.perf.stallNoWay
              << " mergeBlocked=" << r.perf.stallMergeBlocked
              << " wbSame=" << r.perf.stallWbSame << "]\n";

    std::cout << " queues    : readQ avg=" << r.rdQAvg
              << " writeQ avg=" << r.wrQAvg
              << " wayLock avg=" << r.lockAvg << " max=" << r.lockMax << "\n";

    std::cout << std::setprecision(2);
    if (r.reads) {
        std::cout << " latency R : avg=" << avgOf(r.readService)
                  << " p50=" << pctOf(r.readService, 0.50)
                  << " p95=" << pctOf(r.readService, 0.95)
                  << " p99=" << pctOf(r.readService, 0.99)
                  << " max=" << maxOf(r.readService)
                  << "  (wait avg=" << avgOf(r.readWait) << ")\n";
    }
    if (r.writes) {
        std::cout << " latency W : avg=" << avgOf(r.writeService)
                  << " p50=" << pctOf(r.writeService, 0.50)
                  << " p95=" << pctOf(r.writeService, 0.95)
                  << " p99=" << pctOf(r.writeService, 0.99)
                  << " max=" << maxOf(r.writeService)
                  << "  (wait avg=" << avgOf(r.writeWait) << ")\n";
    }

    if (r.timedOut) std::cout << " !! TIMEOUT\n";
}

static const char* locName(int lc) {
    switch (lc) {
        case LOC_SAME_ADDR:      return "same address";
        case LOC_SAME_LINE_WORD: return "same line, diff word";
        case LOC_DIFF_LINE:      return "different line";
    }
    return "?";
}

static void printClassHeader() {
    std::cout << std::left << std::setw(22) << "class"
              << std::right
              << std::setw(8)  << "reqs"
              << std::setw(8)  << "share%"
              << std::setw(10) << "cacheHit%"
              << std::setw(9)  << "effHit%"
              << std::setw(9)  << "readHit%"
              << std::setw(10) << "writeHit%"
              << std::setw(8)  << "avgLat"
              << std::setw(8)  << "p95"
              << std::setw(8)  << "merges"
              << "\n";
}

static void printClassRow(const std::string& label, const ClassStats& s,
                          uint64_t total) {
    const double share = total ? 100.0 * s.reqs / total : 0.0;
    std::cout << std::left << std::setw(22) << label << std::right
              << std::setw(8)  << s.reqs
              << std::setw(8)  << share
              << std::setw(10) << s.cacheHitRate() * 100.0
              << std::setw(9)  << s.effHitRate() * 100.0
              << std::setw(9)  << s.readHitRate() * 100.0
              << std::setw(10) << s.writeHitRate() * 100.0
              << std::setw(8)  << avgOf(s.service)
              << std::setw(8)  << pctOf(s.service, 0.95)
              << std::setw(8)  << s.merges
              << "\n";
}

static void printPhaseBreakdown(const PhaseReport& r) {
    std::cout << "\n=== phase breakdown ===\n";
    printClassHeader();
    printClassRow("60% same-address", r.phase[0], r.requests);
    printClassRow("0% random",        r.phase[1], r.requests);
}

static void printLocalityBreakdown(const PhaseReport& r,
                                   const LocalityWorkload& wl) {
    std::cout << "\n=== locality breakdown ===\n";
    std::cout << " transitions: same-address=" << wl.sameAddr
              << " same-line-diff-word=" << wl.sameLine
              << " different-line=" << wl.diffLine
              << " (total " << wl.total() << ")\n";
    printClassHeader();
    for (int lc = 0; lc < LOC_CLASSES; ++lc)
        printClassRow(locName(lc), r.loc[lc], r.requests);
}

static void printPhaseClassMatrix(const PhaseReport& r) {
    std::cout << "\n=== phase x locality ===\n";
    std::cout << std::left << std::setw(22) << "class"
              << std::right
              << std::setw(9) << "60% reqs"
              << std::setw(9) << "60% eff%"
              << std::setw(9) << "60% lat"
              << std::setw(9) << "0% reqs"
              << std::setw(9) << "0% eff%"
              << std::setw(9) << "0% lat"
              << "\n";
    std::cout << std::fixed << std::setprecision(2);
    for (int lc = 0; lc < LOC_CLASSES; ++lc) {
        const ClassStats& a = r.phaseLoc[0][lc];
        const ClassStats& b = r.phaseLoc[1][lc];
        std::cout << std::left << std::setw(22) << locName(lc) << std::right
                  << std::setw(9) << a.reqs
                  << std::setw(9) << a.effHitRate() * 100.0
                  << std::setw(9) << avgOf(a.service)
                  << std::setw(9) << b.reqs
                  << std::setw(9) << b.effHitRate() * 100.0
                  << std::setw(9) << avgOf(b.service)
                  << "\n";
    }
}

static void printObservations(const PhaseReport& r,
                              const LocalityWorkload& wl) {
    std::cout << "\n=== observations ===\n";
    std::cout << std::fixed << std::setprecision(2);

    std::cout << "- 60% 阶段 eff-hit " << r.phase[0].effHitRate() * 100.0
              << "%，0% 阶段 " << r.phase[1].effHitRate() * 100.0
              << "%；时间局部性带来的命中率差约 "
              << (r.phase[0].effHitRate() - r.phase[1].effHitRate()) * 100.0
              << " 个百分点。\n";

    std::cout << "- 同地址事务 eff-hit " << r.loc[LOC_SAME_ADDR].effHitRate() * 100.0
              << "%，不同行事务 " << r.loc[LOC_DIFF_LINE].effHitRate() * 100.0
              << "%。\n";

    std::cout << "- 同行不同字（空间局部性）事务 " << r.loc[LOC_SAME_LINE_WORD].reqs
              << " 条，占 "
              << (r.requests ? 100.0 * r.loc[LOC_SAME_LINE_WORD].reqs / r.requests : 0.0)
              << "%，eff-hit "
              << r.loc[LOC_SAME_LINE_WORD].effHitRate() * 100.0
              << "%。\n";

    std::cout << "- MSHR 合并：读 " << r.perf.readMerges
              << " 次，写 " << r.perf.writeMerges
              << " 次；mshrAllocs=" << r.perf.mshrAllocs << "。\n";

    std::cout << "- 写回：" << r.perf.writebacks
              << " 行；dirty evictions=" << r.perf.dirtyEvictions
              << "；WBB 满冻结 " << r.perf.stallWbbFull << " 拍。\n";

    std::cout << "- Stage2 冻结 " << r.perf.s2StallCycles
              << " 拍（mshrFull=" << r.perf.stallMshrFull
              << "，wbbFull=" << r.perf.stallWbbFull
              << "，wbSame=" << r.perf.stallWbSame << "）。\n";

    std::cout << "- 工作集 1024 行（64KB），Cache 128 行（8KB）；"
              << "60% 阶段靠同地址重复抵消容量不足，0% 阶段退化为 8 倍容量的随机访问。\n";

    const uint64_t blocksPerPhase = (wl.total() / 100) / 2;
    const uint64_t phase0Transitions =
        (wl.phaseReqs[0] > blocksPerPhase) ? (wl.phaseReqs[0] - blocksPerPhase) : 0;

    std::cout << "- 60% 阶段同地址 " << wl.sameAddr << " 条（占该阶段 "
              << (wl.phaseReqs[0] ? 100.0 * wl.sameAddr / wl.phaseReqs[0] : 0.0)
              << "%；去掉每个 block 的首条后为 "
              << (phase0Transitions ? 100.0 * wl.sameAddr / phase0Transitions : 0.0)
              << "%），0% 阶段同地址 0 条。\n";

    std::cout << "- 全局同地址占比 "
              << (wl.total() ? 100.0 * wl.sameAddr / wl.total() : 0.0)
              << "%，同行不同字占比 "
              << (wl.total() ? 100.0 * wl.sameLine / wl.total() : 0.0)
              << "%。\n";
}

// -------------------------------------------------------------
int main() {
    const uint64_t N    = 1024ull * 50;   // 51,200
    const uint32_t SEED = 0x5EED1234u;

    std::cout << "================================================================\n";
    std::cout << " CacheTop locality performance test\n";
    std::cout << " workload : 1024 cache lines = 64KB, " << N << " L/S\n";
    std::cout << " pattern  : 100 inst @ 60% same-address -> 100 inst @ 0% -> repeat\n";
    std::cout << " L/S      : 50/50 random, store data random\n";
    std::cout << " params   : sets=" << NUM_SETS << " ways=" << NUM_WAYS
              << " block=" << BLOCK_SIZE << "B"
              << " MSHR=" << MSHR_ENTRIES
              << " WBB=" << WBB_ENTRIES << "\n";
    std::cout << " memory   : rdLat=8, wrLat=8 (external assumption)\n";
    std::cout << "================================================================\n";

    LocalityWorkload wl = genLocalityBurst(N, SEED);

    Harness h(8, 8);
    h.runBatch(wl.reqs);
    PhaseReport r = h.report("locality_burst");

    printReport(r);
    printPhaseBreakdown(r);
    printLocalityBreakdown(r, wl);
    printPhaseClassMatrix(r);
    printObservations(r, wl);

    // ---------- 一致性检查 ----------
    assert(r.requests == N);
    assert(r.phase[0].reqs == wl.phaseReqs[0]);
    assert(r.phase[1].reqs == wl.phaseReqs[1]);
    assert(r.phase[0].reqs + r.phase[1].reqs == N);

    assert(r.loc[LOC_SAME_ADDR].reqs == wl.sameAddr);
    assert(r.loc[LOC_SAME_LINE_WORD].reqs == wl.sameLine);
    assert(r.loc[LOC_DIFF_LINE].reqs == wl.diffLine);
    assert(r.loc[0].reqs + r.loc[1].reqs + r.loc[2].reqs == N);

    // 0% 阶段不应出现同地址
    assert(r.phaseLoc[1][LOC_SAME_ADDR].reqs == 0);
    assert(r.phaseLoc[0][LOC_SAME_ADDR].reqs == wl.sameAddr);

    // phase x locality 的行/列和应与 phase / loc 一致
    for (int lc = 0; lc < LOC_CLASSES; ++lc)
        assert(r.phaseLoc[0][lc].reqs + r.phaseLoc[1][lc].reqs == r.loc[lc].reqs);
    for (int p = 0; p < 2; ++p) {
        uint64_t sum = 0;
        for (int lc = 0; lc < LOC_CLASSES; ++lc)
            sum += r.phaseLoc[p][lc].reqs;
        assert(sum == r.phase[p].reqs);
    }

    // 分类汇总应与整体计数器一致
    uint64_t readHits = 0, writeHits = 0, readMerges = 0, writeMerges = 0;
    uint64_t reads = 0, writes = 0;
    for (int lc = 0; lc < LOC_CLASSES; ++lc) {
        readHits   += r.loc[lc].readHits;
        writeHits  += r.loc[lc].writeHits;
        readMerges += r.loc[lc].readMerges;
        writeMerges += r.loc[lc].writeMerges;
        reads      += r.loc[lc].reads;
        writes     += r.loc[lc].writes;
    }
    assert(reads  == r.perf.cpuReads);
    assert(writes == r.perf.cpuWrites);
    assert(readHits   == r.perf.readHits);
    assert(writeHits  == r.perf.writeHits);
    assert(readMerges == r.perf.readMerges);
    assert(writeMerges == r.perf.writeMerges);

    std::cout << "\n=== locality performance test done ===\n";
    return 0;
}
