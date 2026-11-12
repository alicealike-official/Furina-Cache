// test_policy.cpp
// =============================================================
// 替换策略单元测试 + CacheTop 模板注入的编译/实例化检查
//
// 对应文档：§10.1（可插拔）、§10.3（onHit/onFill 契约）、
//           §10.4（victim 选择：优先空且未锁 / 跳过锁定路 / 全锁不可用）
//
// 编译运行：
//   make run-policy
// =============================================================

#include "CacheTop.hpp"
#include "ReplacePolicy.hpp"

#include <array>
#include <cassert>
#include <deque>
#include <iostream>
#include <type_traits>
#include <utility>
#include <vector>

using namespace dcache;

using ValidVec  = std::array<bool, NUM_WAYS>;
using LockedVec = std::array<bool, NUM_WAYS>;

// -------------------------------------------------------------
// 所有策略都必须满足的公共契约（§10.4）
// -------------------------------------------------------------
template <typename Policy>
static void checkCommonContract(const char* name) {
    Policy p;                       // 构造即 reset

    // 1) 全空、全未锁 -> 低下标（way0）
    ValidVec  valid{};
    LockedVec locked{};
    assert(p.getVictim(0, valid, locked) == 0);

    // 2) 空路被锁时不能选，必须跳过
    locked[0] = true;
    assert(p.getVictim(0, valid, locked) == 1);
    assert(p.getVictim(0, valid, locked) == 1);   // 纯函数，可重复调用

    // 3) 全 valid、只有 way2 未锁 -> way2
    valid  = ValidVec{ true, true, true, true };
    locked = LockedVec{ true, true, false, true };
    assert(p.getVictim(0, valid, locked) == 2);

    // 4) 全部被锁 -> -1（请求不可接收）
    locked = LockedVec{ true, true, true, true };
    assert(p.getVictim(0, valid, locked) == -1);

    // 5) 不同 set 的状态互相独立
    ValidVec  v1{};
    LockedVec l1{};
    assert(p.getVictim(1, v1, l1) == 0);

    std::cout << "  [" << name << "] common contract ok\n";
}

// -------------------------------------------------------------
// FIFO：命中不改变顺序，填充移到队尾
// -------------------------------------------------------------
static void testFifoOrder() {
    FifoPolicy p;
    ValidVec  valid{ true, true, true, true };
    LockedVec locked{};

    assert(p.getVictim(0, valid, locked) == 0);      // 初始顺序 0,1,2,3
    p.onHit(0, 0);                                   // FIFO 忽略命中
    assert(p.getVictim(0, valid, locked) == 0);
    p.onFill(0, 0);                                  // 0 移队尾 -> 1,2,3,0
    assert(p.getVictim(0, valid, locked) == 1);
    p.onFill(0, 1);                                  // -> 2,3,0,1
    assert(p.getVictim(0, valid, locked) == 2);

    // 队首被锁时按顺序跳过
    locked[2] = true;
    assert(p.getVictim(0, valid, locked) == 3);

    std::cout << "  [FIFO] order evolution ok\n";
}

// -------------------------------------------------------------
// LRU：命中与填充都把该路移到队尾
// -------------------------------------------------------------
static void testLruOrder() {
    LruPolicy p;
    ValidVec  valid{ true, true, true, true };
    LockedVec locked{};

    assert(p.getVictim(0, valid, locked) == 0);
    p.onHit(0, 0);                                   // -> 1,2,3,0
    assert(p.getVictim(0, valid, locked) == 1);
    p.onHit(0, 1);                                   // -> 2,3,0,1
    assert(p.getVictim(0, valid, locked) == 2);
    p.onFill(0, 2);                                  // -> 3,0,1,2
    assert(p.getVictim(0, valid, locked) == 3);

    std::cout << "  [LRU] order evolution ok\n";
}

// -------------------------------------------------------------
// Tree-PLRU：树位决定偏好序；访问把路径位指向"远离该路"
// -------------------------------------------------------------
static void testPlruOrder() {
    PlruPolicy p;
    ValidVec  valid{ true, true, true, true };
    LockedVec locked{};

    // 复位：所有树位为 0 -> 偏好序 0,1,2,3
    assert(p.getVictim(0, valid, locked) == 0);

    // 访问 way2：node3 的位指向"远离 2"（左），root 指向"远离 2 的半区"（左）
    p.onFill(0, 2);
    assert(p.getVictim(0, valid, locked) == 0);      // root 仍优先左半区

    // 访问 way0：node2 位指向右，root 指向右半区 -> 首选 way3
    p.onHit(0, 0);
    assert(p.getVictim(0, valid, locked) == 3);

    // 锁住首选 way3：应回退到同父的 way2
    locked[3] = true;
    assert(p.getVictim(0, valid, locked) == 2);

    // reset 后回到 way0
    p.reset();
    locked = LockedVec{};
    assert(p.getVictim(0, valid, locked) == 0);

    std::cout << "  [PLRU] tree preference ok\n";
}

// -------------------------------------------------------------
// 策略状态在"淘汰被中止"时不能被破坏
// （getVictim 是纯函数：反复调用不改变内部顺序）
// -------------------------------------------------------------
template <typename Policy>
static void checkPurity(const char* name) {
    Policy p;
    ValidVec  valid{ true, true, true, true };
    LockedVec locked{};
    p.onFill(0, 2);                                  // 建立一个非平凡状态
    const int a = p.getVictim(0, valid, locked);
    for (int i = 0; i < 5; ++i)
        assert(p.getVictim(0, valid, locked) == a);
    std::cout << "  [" << name << "] getVictim is pure ok\n";
}

// -------------------------------------------------------------
// §10.4 的关键语义：队首被锁时，必须在"剔除锁定项后的策略顺序"里取，
// 而不是按 way 编号向后扫描。
// 顺序 [2,0,3,1]、锁 way2 -> 候选是 way0（次老），不是编号相邻的 way3。
// -------------------------------------------------------------
template <typename Policy>
static void checkLockedHeadSkipsWithinOrder(const char* name) {
    Policy p;
    ValidVec  valid{ true, true, true, true };
    LockedVec locked{};

    // 从 [0,1,2,3] 依次 touch 2,0,3,1 -> 顺序 [2,0,3,1]
    p.onFill(0, 2);
    p.onFill(0, 0);
    p.onFill(0, 3);
    p.onFill(0, 1);
    assert(p.getVictim(0, valid, locked) == 2);

    locked[2] = true;
    assert(p.getVictim(0, valid, locked) == 0);   // 次老；按下标扫描会错选 3

    std::cout << "  [" << name << "] locked-head -> next in order ok\n";
}

// -------------------------------------------------------------
// CacheTop 模板注入：三种策略的实例化与一拍运行
// -------------------------------------------------------------
static void checkCacheTopTemplates() {
    static_assert(!std::is_same<CacheTop, CacheTopLru>::value, "alias 不应等价");
    static_assert(!std::is_same<CacheTopLru, CacheTopPlru>::value, "alias 不应等价");

    CacheTop     fifoTop;   // = CacheTopT<FifoPolicy>，默认
    CacheTopLru  lruTop;
    CacheTopPlru plruTop;

    // 空输入跑两拍：只走组合求值 + 时钟沿，不产生任何响应
    for (int i = 0; i < 2; ++i) {
        fifoTop.eval();  fifoTop.tick();
        lruTop.eval();   lruTop.tick();
        plruTop.eval();  plruTop.tick();
    }
    assert(!fifoTop.memReadReq_valid && !fifoTop.memWriteReq_valid);
    assert(!lruTop.memReadReq_valid && !lruTop.memWriteReq_valid);
    assert(!plruTop.memReadReq_valid && !plruTop.memWriteReq_valid);

    std::cout << "  [CacheTopT] 3 policy instantiations ok\n";
}

// -------------------------------------------------------------
// 端到端：同一 set 填满 4 路后，命中一次再淘汰，
// 用不同策略应淘汰不同的 victim（验证模板注入真的生效）。
//
//   FIFO : 命中不改变顺序        -> 淘汰 way0（tag0）
//   LRU  : 命中把 way0 移到队尾  -> 淘汰 way1（tag1）
//   PLRU : 命中与填充都更新树位  -> 淘汰 way2（tag2）
// -------------------------------------------------------------
template <typename Top>
struct MiniHarness {
    Top top;
    std::deque<std::pair<Addr, CpuId>> pending;
    std::vector<CpuId> got;
    CpuId nextId = 1;

    bool  rdPend = false;
    BusId rdId   = 0;
    Line  rdLine{};
    bool  wrPend = false;
    BusId wrId   = 0;

    MiniHarness() {
        top.memReadReq_ready   = true;
        top.memWriteReq_ready  = true;
        top.cpuReadResp_ready  = true;
        top.cpuWriteResp_ready = true;
        top.cpu_valid          = false;
        top.memReadResp_valid  = false;
        top.memWriteResp_valid = false;
    }

    static Line lineFor(Addr a) {
        const Addr base = a & ~OFFSET_MASK;
        Line l{};
        for (int i = 0; i < WORDS_PER_BLOCK; ++i)
            l[i] = static_cast<Word>(base * 2654435761u) ^
                   (static_cast<Word>(i) * 0x9E3779B9u);
        return l;
    }

    void cycle() {
        top.cpu_valid = !pending.empty();
        if (top.cpu_valid) {
            top.cpu_addr  = pending.front().first;
            top.cpu_wrEn  = false;
            top.cpu_wData = 0;
            top.cpu_id    = pending.front().second;
        } else {
            top.cpu_addr = 0; top.cpu_wrEn = false; top.cpu_wData = 0; top.cpu_id = 0;
        }

        // 上一拍排定的内存响应
        top.memReadResp_valid  = rdPend;
        top.memReadResp_id     = rdId;
        top.memReadResp_line   = rdLine;
        top.memWriteResp_valid = wrPend;
        top.memWriteResp_id    = wrId;
        rdPend = false;
        wrPend = false;

        top.eval();
        const bool accepted = top.cpu_valid && top.cpu_ready;

        const bool rdFire = top.memReadReq_valid && top.memReadReq_ready;
        const BusId rdFireId = top.memReadReq_id;
        const Addr  rdFireAddr = top.memReadReq_addr;
        const bool wrFire = top.memWriteReq_valid && top.memWriteReq_ready;
        const BusId wrFireId = top.memWriteReq_id;

        top.tick();

        if (accepted) pending.pop_front();
        if (top.cpuReadResp_valid && top.cpuReadResp_ready)
            got.push_back(top.cpuReadResp_id);

        // 读响应延迟一拍（MSHR 要求响应不早于 SEND->MISS_WAIT 的下一拍）
        if (rdFire) { rdPend = true; rdId = rdFireId; rdLine = lineFor(rdFireAddr); }
        if (wrFire) { wrPend = true; wrId = wrFireId; }
    }

    void read(Addr a, int maxCycles = 500) {
        const size_t before = got.size();
        pending.push_back({ a, nextId++ });
        for (int i = 0; i < maxCycles && got.size() == before; ++i) cycle();
        assert(got.size() > before && "读请求超时");
    }
};

static Addr addrOfTag(Tag t) {
    return static_cast<Addr>(t) << (INDEX_WIDTH + OFFSET_WIDTH);
}

template <typename Top>
static void testVictimChoiceE2E(const char* name, Tag expectEvicted) {
    MiniHarness<Top> h;

    // 同 set 依次填 way0..way3（都 miss，选空路）
    for (Tag t = 0; t < 4; ++t) h.read(addrOfTag(t));

    // 命中 tag0：LRU/PLRU 都会更新状态，FIFO 不受影响
    h.read(addrOfTag(0));

    // 再访问 tag4：必须淘汰一路
    h.read(addrOfTag(4));

    bool evictedStillThere = false;
    for (int w = 0; w < NUM_WAYS; ++w)
        if (h.top.cache().getValid(0, w) && h.top.cache().getTag(0, w) == expectEvicted)
            evictedStillThere = true;

    assert(!evictedStillThere && "victim 选择与策略不符");
    std::cout << "  [" << name << "] end-to-end victim = tag" << expectEvicted
              << " ok\n";
}

// -------------------------------------------------------------
int main() {
    std::cout << "=== ReplacePolicy tests ===\n";

    checkCommonContract<FifoPolicy>("FIFO");
    checkCommonContract<LruPolicy>("LRU");
    checkCommonContract<PlruPolicy>("PLRU");

    testFifoOrder();
    testLruOrder();
    testPlruOrder();

    checkPurity<FifoPolicy>("FIFO");
    checkPurity<LruPolicy>("LRU");
    checkPurity<PlruPolicy>("PLRU");

    // §10.4：队首被锁时在策略序里顺延（顺序型策略）
    checkLockedHeadSkipsWithinOrder<FifoPolicy>("FIFO");
    checkLockedHeadSkipsWithinOrder<LruPolicy>("LRU");

    // FIFO 淘汰 way0（tag0）；LRU 淘汰 way1（tag1）；PLRU 淘汰 way2（tag2）
    testVictimChoiceE2E<CacheTop>("FIFO", 0);
    testVictimChoiceE2E<CacheTopLru>("LRU", 1);
    testVictimChoiceE2E<CacheTopPlru>("PLRU", 2);

    checkCacheTopTemplates();

    std::cout << "=== all ReplacePolicy tests passed ===\n";
    return 0;
}
