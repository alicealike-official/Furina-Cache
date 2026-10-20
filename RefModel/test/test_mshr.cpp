// test_mshr.cpp
// =============================================================
// MSHR 黑盒测试
//
// 只依据《Cache 架构设计文档 v2》第 7 章（7.1 - 7.14）、12.4、13
// 以及 MSHR 的公开接口编写。
//
// 覆盖点：
//   T1 生命周期：alloc -> SEND -> MISS_WAIT -> FILL -> fill -> replay -> release
//   T2 合并：SEND/MISS_WAIT 可合并、Slot 上限、hasWriteSlot
//   T3 重放数据：读旁路（fillData + 前序同字写）、写只回响应、dirty 规则
//   T4 多条目重放轮询（文档 7.12）
//   T5 match / hasFree / full，以及 FILL 不可合并（文档 7.4）
//
// 编译（在 RefModel 目录下）：
//   make run-mshr
// =============================================================

#include "MSHR.hpp"

#include <cassert>
#include <iostream>

using namespace dcache;

// -------------------------------------------------------------
static Line makeLine(Word base) {
    Line l{};
    for (int i = 0; i < WORDS_PER_BLOCK; ++i)
        l[i] = base + static_cast<Word>(i);
    return l;
}

static Addr expectBlockAddr(Tag t, int idx) {
    return (static_cast<Addr>(t) << (INDEX_WIDTH + OFFSET_WIDTH)) |
           (static_cast<Addr>(idx) << OFFSET_WIDTH);
}

// 走一拍并做不变量自检
static void tick(MSHR& m) {
    m.tick();
    assert(m.checkInvariants());
}

// -------------------------------------------------------------
// T1：完整生命周期
// -------------------------------------------------------------
static void test_lifecycle() {
    std::cout << "[T1] 生命周期 alloc->SEND->MISS_WAIT->FILL->replay->release ... ";

    MSHR m;
    const Tag   T    = 0x123;
    const int   IDX  = 5;
    const int   WAY  = 2;
    const int   WOFF = 3;
    const CpuId RID  = 7;

    // 分配（读）
    m.alloc_req = MSHR::AllocReq{ true, T, IDX, WAY, false, 0, WOFF, RID, -1 };
    tick(m);
    m.alloc_req = MSHR::AllocReq{};

    auto mi = m.match(T, IDX);
    assert(mi.hit && mi.state == MSHR::State::SEND && mi.mergeable);
    assert(m.validEntries() == 1);

    // 发送
    auto s = m.sendReq();
    assert(s.en && s.id == 0);
    assert(s.addr == expectBlockAddr(T, IDX));
    m.mem_rd_ready = true;
    tick(m);
    m.mem_rd_ready = false;
    assert(m.entry(0).state == MSHR::State::MISS_WAIT);
    assert(!m.sendReq().en);                  // 已无 SEND 条目

    // 内存响应
    const Line L = makeLine(0x1000);
    m.mem_rd_resp = MSHR::MemRdResp{ true, 0, L };
    tick(m);
    m.mem_rd_resp = MSHR::MemRdResp{};
    assert(m.entry(0).state == MSHR::State::FILL);

    // 填充（纯读 -> dirty=false）
    auto f = m.fillReq();
    assert(f.en && f.entry == 0 && f.index == IDX && f.way == WAY && f.tag == T);
    assert(!f.dirty);
    assert(f.line == L);
    tick(m);                                  // fill_ready 默认 true
    assert(!m.fillReq().en);

    // 重放（读）
    auto r = m.replayReq();
    assert(r.en && r.slot == 0 && !r.isWrite && r.respID == RID);
    assert(r.rData == L[WOFF]);
    m.replay_ready = true;
    tick(m);
    m.replay_ready = false;

    // 已释放
    assert(!m.match(T, IDX).hit);
    assert(m.hasFree());
    assert(m.validEntries() == 0);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T2：合并与 Slot 上限
// -------------------------------------------------------------
static void test_merge() {
    std::cout << "[T2] 合并 / Slot 上限 ... ";

    MSHR m;
    const Tag T = 0x200;
    const int IDX = 1;

    m.alloc_req = MSHR::AllocReq{ true, T, IDX, 0, false, 0, 2, 1, -1 };
    tick(m);
    m.alloc_req = MSHR::AllocReq{};

    auto mi = m.match(T, IDX);
    assert(mi.mergeable && mi.slotFree && mi.freeSlot == 1);

    // 合并一个写
    m.merge_req = MSHR::MergeReq{ true, mi.entry, true, 0xDEADBEEF, 2, 2 };
    tick(m);
    m.merge_req = MSHR::MergeReq{};

    const auto& e = m.entry(0);
    assert(e.validCnt == 2);
    assert(e.hasWriteSlot);
    assert(e.slots[1].isWrite && e.slots[1].wData == 0xDEADBEEF &&
           e.slots[1].wordOff == 2);

    // 继续合并直到 Slot 满
    for (int k = e.validCnt; k < MSHR_MAX_PENDING; ++k) {
        mi = m.match(T, IDX);
        assert(mi.slotFree && mi.freeSlot == k);
        m.merge_req = MSHR::MergeReq{
            true, mi.entry, false, 0, k, static_cast<CpuId>(10 + k) };
        tick(m);
        m.merge_req = MSHR::MergeReq{};
    }

    mi = m.match(T, IDX);
    assert(mi.slotFree == false && mi.freeSlot == -1);
    assert(m.entry(0).validCnt == MSHR_MAX_PENDING);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T3：重放数据来源与 dirty 规则
// -------------------------------------------------------------
static void test_replay_data() {
    std::cout << "[T3] 重放读旁路 / dirty ... ";

    MSHR m;
    const Tag T = 0x300;
    const int IDX = 2;
    const int WOFF = 1;

    // slot0: 读
    m.alloc_req = MSHR::AllocReq{ true, T, IDX, 0, false, 0, WOFF, 0, -1 };
    tick(m);
    m.alloc_req = MSHR::AllocReq{};

    // slot1: 写（同一字）
    auto mi = m.match(T, IDX);
    m.merge_req = MSHR::MergeReq{ true, mi.entry, true, 0xAAAA, WOFF, 1 };
    tick(m);
    m.merge_req = MSHR::MergeReq{};

    // slot2: 读（同一字，位于写之后）
    mi = m.match(T, IDX);
    m.merge_req = MSHR::MergeReq{ true, mi.entry, false, 0, WOFF, 2 };
    tick(m);
    m.merge_req = MSHR::MergeReq{};

    // SEND -> MISS_WAIT -> FILL
    auto s = m.sendReq();
    assert(s.en);
    m.mem_rd_ready = true;
    tick(m);
    m.mem_rd_ready = false;

    const Line L = makeLine(0x7000);
    m.mem_rd_resp = MSHR::MemRdResp{ true, 0, L };
    tick(m);
    m.mem_rd_resp = MSHR::MemRdResp{};

    // 填充：dirty=true，mergedData 把写覆盖到对应字
    auto f = m.fillReq();
    assert(f.en && f.dirty);
    Line expect = L;
    expect[WOFF] = 0xAAAA;
    assert(f.line == expect);
    tick(m);

    // slot0（读）：之前没有同字写 -> fillData
    auto r0 = m.replayReq();
    assert(r0.en && r0.slot == 0 && !r0.isWrite && r0.rData == L[WOFF]);
    m.replay_ready = true;
    tick(m);
    m.replay_ready = false;

    // slot1（写）：只回写响应
    auto r1 = m.replayReq();
    assert(r1.en && r1.slot == 1 && r1.isWrite && r1.respID == 1);
    m.replay_ready = true;
    tick(m);
    m.replay_ready = false;

    // slot2（读）：前序同字写旁路 -> 0xAAAA（不是 Cache 里的值）
    auto r2 = m.replayReq();
    assert(r2.en && r2.slot == 2 && !r2.isWrite && r2.rData == 0xAAAA);
    m.replay_ready = true;
    tick(m);
    m.replay_ready = false;

    assert(!m.match(T, IDX).hit);
    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T4：多条目重放轮询
// -------------------------------------------------------------
static void test_replay_round_robin() {
    std::cout << "[T4] 多条目重放轮询 ... ";

    MSHR m;
    // 两个条目（不同 tag、同一 index 也是允许的）
    for (int k = 0; k < 2; ++k) {
        m.alloc_req = MSHR::AllocReq{
            true, static_cast<Tag>(0xA + k), 0, 0, false, 0, 0,
            static_cast<CpuId>(k), -1 };
        tick(m);
        m.alloc_req = MSHR::AllocReq{};
    }

    // 依次发送
    for (int k = 0; k < 2; ++k) {
        auto s = m.sendReq();
        assert(s.en && s.entry == k);          // 低位优先
        m.mem_rd_ready = true;
        tick(m);
        m.mem_rd_ready = false;
    }

    // 依次返回内存读响应
    for (int k = 0; k < 2; ++k) {
        m.mem_rd_resp = MSHR::MemRdResp{
            true, static_cast<BusId>(k), makeLine(0x100u * k) };
        tick(m);
        m.mem_rd_resp = MSHR::MemRdResp{};
    }

    // 依次填充（每拍一个）
    for (int k = 0; k < 2; ++k) {
        auto f = m.fillReq();
        assert(f.en);
        tick(m);
    }
    assert(!m.fillReq().en);

    // 重放应从 entry0 -> entry1 轮询
    auto r0 = m.replayReq();
    assert(r0.en && r0.entry == 0);
    m.replay_ready = true;
    tick(m);
    m.replay_ready = false;

    auto r1 = m.replayReq();
    assert(r1.en && r1.entry == 1);

    m.replay_ready = true;
    tick(m);
    m.replay_ready = false;

    assert(m.validEntries() == 0);
    std::cout << "ok\n";
}

// -------------------------------------------------------------
// T5：match / hasFree / full，FILL 不可合并
// -------------------------------------------------------------
static void test_match_and_full() {
    std::cout << "[T5] match / hasFree / full ... ";

    MSHR m;
    assert(m.hasFree() && !m.full());

    // 占满 4 个条目
    for (int i = 0; i < MSHR_ENTRIES; ++i) {
        m.alloc_req = MSHR::AllocReq{
            true, static_cast<Tag>(0x10 + i), 0, 0, false, 0, 0,
            static_cast<CpuId>(i), -1 };
        tick(m);
        m.alloc_req = MSHR::AllocReq{};
    }
    assert(m.full() && !m.hasFree());
    assert(m.validEntries() == MSHR_ENTRIES);

    // 让 entry0 进入 FILL
    m.mem_rd_ready = true;
    auto s = m.sendReq();
    assert(s.en && s.entry == 0);
    tick(m);
    m.mem_rd_ready = false;

    m.mem_rd_resp = MSHR::MemRdResp{ true, 0, makeLine(0) };
    tick(m);
    m.mem_rd_resp = MSHR::MemRdResp{};

    // FILL 命中但不可合并
    auto mi = m.match(0x10, 0);
    assert(mi.hit && mi.state == MSHR::State::FILL && !mi.mergeable);

    // 其他条目的同 index 不同 tag 仍可合并（SEND）
    auto mi2 = m.match(0x11, 0);
    assert(mi2.hit && mi2.mergeable && mi2.slotFree);

    // 不存在的行
    auto mi3 = m.match(0x99, 0);
    assert(!mi3.hit);

    std::cout << "ok\n";
}

// -------------------------------------------------------------
int main() {
    std::cout << "=== MSHR black-box test ===\n";

    test_lifecycle();
    test_merge();
    test_replay_data();
    test_replay_round_robin();
    test_match_and_full();

    std::cout << "=== all MSHR tests passed ===\n";
    return 0;
}
