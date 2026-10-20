// MSHR.hpp
#pragma once
#include "params.hpp"
#include <array>
#include <cassert>
#include <cstdint>
#include <iomanip>
#include <iostream>

namespace dcache {

// =============================================================
// Layer 1 : MSHR 未命中状态保持寄存器
//
// 对应文档第 7 章（7.1 - 7.14）、12.4、13（不变量一/二/四/五）。
//
// 职责（本层实现）：
//   - Entry/Slot 结构                         （7.2）
//   - IDLE / SEND / MISS_WAIT / FILL 状态机     （7.3）
//   - 同地址匹配与可合并性查询                  （7.4 / 7.5）
//   - Slot 追加与到达顺序                      （7.5 / 7.6）
//   - 发送仲裁（低位优先）+ 载荷锁存             （7.7）
//   - 内存读响应 -> fillData，MISS_WAIT->FILL   （7.8）
//   - mergedData 合并 + dirty 规则              （7.9 / 7.10）
//   - FILL 首拍 W2 填充请求                     （7.11）
//   - Replay（条目内合并视图，不读 Cache）       （7.11）
//   - 多 Entry Replay 轮询                      （7.12）
//   - 条目释放（重放完最后一个 Slot）             （7.13）
//
// 本层明确不做（属于 Layer 2 / Layer 3）：
//   CPU 请求流水线、Stage1 估计 / Stage2 权威提交的仲裁、
//   Stage2 冻结、cpuReady 反压合成、victim 选择、Way Lock、
//   WBB 预留、响应队列。
//
// 时序约定（松散时序，与 CacheMem / WriteBackBuffer 对齐）：
//   - 每拍分两步：
//       (1) 外部布置 *_req 字段，并读取组合输出
//           match() / hasFree() / full() / sendReq() /
//           fillReq() / replayReq()
//       (2) 调用 tick()，表示本拍时钟沿
//   - tick() 内的一切状态更新都基于"本拍开始时的状态"求值。
//
// 关于 sendReq() / fillReq() 的"调用即提交"约定：
//   - sendReq()：仲裁器选中某条目后，其载荷必须锁存到总线接受为止，
//     不可抢占（文档 7.7）。因此首次调用会锁存仲裁结果并一直返回它，
//     直到 tick() 中 mem_rd_ready 握手成功或 reset()。
//   - fillReq()：调用即表示"本拍把该条目的填充提交给 W2"，
//     tick() 只在调用过 fillReq() 时才把 fillDone 置位。
//   两者都必须在 tick() 之前调用。
// =============================================================

#ifndef DCACHE_MSHR_ASSERT
#  if defined(NDEBUG)
#    define DCACHE_MSHR_ASSERT(x) ((void)0)
#  else
#    define DCACHE_MSHR_ASSERT(x) assert(x)
#  endif
#endif

class MSHR {
public:
    enum class State { IDLE, SEND, MISS_WAIT, FILL };

    // ---------- Slot（文档 7.2） ----------
    struct Slot {
        bool  valid   = false;   // 该槽位是否有效
        bool  isWrite = false;   // 读还是写
        Word  wData   = 0;       // 写数据
        int   wordOff = 0;       // 行内字偏移
        CpuId respID  = 0;       // 返回 CPU 时使用的请求 ID
    };

    // ---------- Entry（文档 7.2） ----------
    struct Entry {
        bool   valid      = false;
        Tag    tag        = 0;
        int    index      = 0;      // set 号
        int    allocWay   = 0;      // 为该行分配的 Cache 路
        Line   fillData{};          // 内存返回的原始整行
        std::array<Slot, MSHR_MAX_PENDING> slots{};
        State  state      = State::IDLE;
        int    replayCnt  = 0;      // 当前重放到第几个 Slot
        int    validCnt   = 0;      // 需要重放的 Slot 数（也是下一个空槽下标）
        bool   hasWriteSlot = false; // 是否含写请求（决定填充 dirty）
        int    wbSlotIdx  = -1;     // 已预留的 WBB 槽位（victim 脏时有效）
        bool   fillDone   = false;  // FILL 首拍的 W2 填充是否已完成
    };

    // ---------- 上游：分配（Stage2 权威提交） ----------
    struct AllocReq {
        bool  en        = false;
        Tag   tag       = 0;
        int   index     = 0;
        int   allocWay  = 0;
        bool  isWrite   = false;
        Word  wData     = 0;
        int   wordOff   = 0;
        CpuId respID    = 0;
        int   wbSlotIdx = -1;
    };

    // ---------- 上游：合并（Stage2 权威提交） ----------
    struct MergeReq {
        bool  en      = false;
        int   entry   = -1;    // 来自 match().entry
        bool  isWrite = false;
        Word  wData   = 0;
        int   wordOff = 0;
        CpuId respID  = 0;
    };

    // ---------- 下游：内存读请求（文档 4.2 / 4.5 / 7.7） ----------
    struct MemRdReq {
        bool  en    = false;
        Addr  addr  = 0;      // 块对齐地址
        BusId id    = 0;      // 条目位次零扩展到总线 ID 宽度
        int   entry = -1;     // 便于观测
    };

    // ---------- 下游：内存读响应（文档 7.8） ----------
    struct MemRdResp {
        bool  en   = false;
        BusId id   = 0;
        Line  line{};
    };

    // ---------- 下游：填充写 Cache（W2，文档 7.11 / 7.10） ----------
    struct FillReq {
        bool  en    = false;
        int   entry = -1;
        int   index = 0;
        int   way   = 0;       // = allocWay
        Tag   tag   = 0;
        bool  dirty = false;   // = hasWriteSlot
        Line  line{};          // = mergedData
    };

    // ---------- 下游：重放（文档 7.11 / 7.12） ----------
    struct ReplayReq {
        bool  en      = false;
        int   entry   = -1;
        int   slot    = -1;
        bool  isWrite = false;
        int   wordOff = 0;
        Word  rData   = 0;     // 读 Slot 的返回数据（写 Slot 无意义）
        CpuId respID  = 0;
    };

    // ---------- 匹配查询（Stage1 估计用，文档 7.4） ----------
    struct MatchInfo {
        bool  hit       = false;
        int   entry     = -1;
        State state     = State::IDLE;
        bool  mergeable = false;   // SEND / MISS_WAIT
        bool  slotFree  = false;
        int   freeSlot  = -1;
    };

    // ---------- 端口输入（由驱动方每拍布置） ----------
    AllocReq   alloc_req;
    MergeReq   merge_req;
    MemRdResp  mem_rd_resp;
    bool       mem_rd_ready = false;   // 总线是否接受 sendReq()
    bool       replay_ready = false;   // 响应队列是否接受 replayReq()
    bool       fill_ready   = true;    // W2 是否可写（文档中通常恒真）

    // ---------- 构造 / 复位（文档 5.6） ----------
    MSHR() { reset(); }

    void reset() {
        for (auto& e : entries_) e = Entry{};
        sendHoldValid_   = false;
        sendHoldEntry_   = -1;
        sendPresented_   = false;
        fillPresented_   = false;
        replayPtr_       = 0;
        alloc_req        = AllocReq{};
        merge_req        = MergeReq{};
        mem_rd_resp      = MemRdResp{};
        mem_rd_ready     = false;
        replay_ready     = false;
        fill_ready       = true;
    }

    // ========== 组合查询（tick 之前读取；纯函数） ==========

    // 同地址匹配：某 Entry 有效且 tag/index 完全一致（文档 7.4）
    MatchInfo match(Tag t, int idx) const {
        MatchInfo m;
        for (int i = 0; i < MSHR_ENTRIES; ++i) {
            const Entry& e = entries_[i];
            if (e.valid && e.tag == t && e.index == idx) {
                m.hit       = true;
                m.entry     = i;
                m.state     = e.state;
                m.mergeable = (e.state == State::SEND || e.state == State::MISS_WAIT);
                m.freeSlot  = (e.validCnt < MSHR_MAX_PENDING) ? e.validCnt : -1;
                m.slotFree  = (m.freeSlot >= 0);
                break;
            }
        }
        return m;
    }

    bool hasFree() const { return freeEntry() >= 0; }
    bool full()    const { return freeEntry() < 0; }

    int validEntries() const {
        int n = 0;
        for (int i = 0; i < MSHR_ENTRIES; ++i)
            if (entries_[i].valid) ++n;
        return n;
    }

    // ========== 组合输出（tick 之前读取） ==========

    // 发送仲裁（文档 7.7）：低位下标优先；首次调用锁存，直到握手或 reset。
    // 调用方必须每拍在 tick() 之前调用一次。
    MemRdReq sendReq() {
        sendPresented_ = true;
        if (!sendHoldValid_) {
            const int sel = pickSend();
            if (sel >= 0) {
                sendHoldEntry_ = sel;
                sendHoldValid_ = true;
            }
        }
        MemRdReq r;
        if (sendHoldValid_) {
            const Entry& e = entries_[sendHoldEntry_];
            r.en    = true;
            r.entry = sendHoldEntry_;
            r.id    = static_cast<BusId>(sendHoldEntry_);   // 零扩展（文档 4.5）
            r.addr  = blockAddr(e.tag, e.index);
        }
        return r;
    }

    // 本拍要执行填充写的条目（文档 7.11 第一拍）；每拍最多一个。
    // 与 sendReq() 一样：调用即表示"本拍把该填充提交给 W2"，
    // tick() 只在调用过 fillReq() 时才把 fillDone 置位。
    FillReq fillReq() {
        fillPresented_ = true;
        FillReq r;
        const int i = pickFill();
        if (i >= 0) {
            const Entry& e = entries_[i];
            r.en    = true;
            r.entry = i;
            r.index = e.index;
            r.way   = e.allocWay;
            r.tag   = e.tag;
            r.dirty = e.hasWriteSlot;        // 文档 7.10
            r.line  = mergedData(e);         // 文档 7.9
        }
        return r;
    }

    // 本拍要重放的 Slot：条目级轮询（文档 7.12），条目内低下标优先（7.6）。
    ReplayReq replayReq() const {
        ReplayReq r;
        const int i = pickReplay();
        if (i >= 0) {
            const Entry& e = entries_[i];
            const Slot&  s = e.slots[e.replayCnt];
            r.en      = true;
            r.entry   = i;
            r.slot    = e.replayCnt;
            r.isWrite = s.isWrite;
            r.wordOff = s.wordOff;
            r.respID  = s.respID;
            r.rData   = s.isWrite ? 0 : replayReadData(e, e.replayCnt);
        }
        return r;
    }

    // ========== 一拍 ==========
    void tick() {
        // ---- 1) 组合求值：全部基于"本拍开始时"的状态 ----
        const int  fillSel   = pickFill();
        const bool fillFire  = fillPresented_ && (fillSel >= 0) && fill_ready;

        const int  replaySel = pickReplay();
        const bool replayFire = (replaySel >= 0) && replay_ready;

        const bool sendFire  = sendPresented_ && sendHoldValid_ && mem_rd_ready;
        const int  sendSel   = sendHoldEntry_;

        const int  allocSel  = freeEntry();   // 拍初空闲条目

        DCACHE_MSHR_ASSERT(!(alloc_req.en && merge_req.en));

        // ---- 2) 沿上更新 ----

        // (a) 内存读响应：MISS_WAIT -> FILL（文档 7.8）
        if (mem_rd_resp.en) {
            const int i = busToEntry(mem_rd_resp.id);
            DCACHE_MSHR_ASSERT(0 <= i && i < MSHR_ENTRIES);
            Entry& e = entries_[i];
            DCACHE_MSHR_ASSERT(e.valid && e.state == State::MISS_WAIT);
            e.fillData  = mem_rd_resp.line;
            e.state     = State::FILL;
            e.fillDone  = false;
            e.replayCnt = 0;
        }

        // (b) 发送握手：SEND -> MISS_WAIT（文档 7.7 / 7.3）
        if (sendFire) {
            DCACHE_MSHR_ASSERT(0 <= sendSel && sendSel < MSHR_ENTRIES);
            Entry& e = entries_[sendSel];
            DCACHE_MSHR_ASSERT(e.valid && e.state == State::SEND);
            e.state       = State::MISS_WAIT;
            sendHoldValid_ = false;
        }
        sendPresented_ = false;

        // (c) 填充完成：FILL 首拍之后标记 fillDone（文档 7.11）
        if (fillFire)
            entries_[fillSel].fillDone = true;
        fillPresented_ = false;

        // (d) 重放一个 Slot（文档 7.11 / 7.12 / 7.13）
        if (replayFire) {
            Entry& e = entries_[replaySel];
            e.replayCnt++;
            replayPtr_ = (replaySel + 1) % MSHR_ENTRIES;
            if (e.replayCnt >= e.validCnt)
                releaseEntry(entries_[replaySel]);
        }

        // (e) 分配新条目（Stage2 权威提交，文档 7.5）
        if (alloc_req.en) {
            DCACHE_MSHR_ASSERT(allocSel >= 0);
            DCACHE_MSHR_ASSERT(!match(alloc_req.tag, alloc_req.index).hit);
            initEntry(entries_[allocSel], alloc_req);
        }

        // (f) 合并到已有条目（Stage2 权威提交，文档 7.5）
        if (merge_req.en) {
            DCACHE_MSHR_ASSERT(0 <= merge_req.entry && merge_req.entry < MSHR_ENTRIES);
            Entry& e = entries_[merge_req.entry];
            DCACHE_MSHR_ASSERT(e.valid);
            DCACHE_MSHR_ASSERT(e.state == State::SEND || e.state == State::MISS_WAIT);
            DCACHE_MSHR_ASSERT(e.validCnt < MSHR_MAX_PENDING);
            appendSlot(e, merge_req);
        }

        // ---- 3) 不变量自检（文档 13） ----
        DCACHE_MSHR_ASSERT(checkInvariants());
    }

    // ========== 不变量自检（文档 13 第一/二/四/五条） ==========
    bool checkInvariants(std::ostream* err = nullptr) const {
        bool ok = true;
        auto fail = [&](const char* m, int i) {
            ok = false;
            if (err) *err << "[MSHR invariant] entry" << i << ": " << m << "\n";
        };

        for (int i = 0; i < MSHR_ENTRIES; ++i) {
            const Entry& e = entries_[i];

            if (!e.valid) {
                if (e.state != State::IDLE)      fail("invalid but not IDLE", i);
                if (e.validCnt != 0)             fail("invalid but validCnt != 0", i);
                if (e.hasWriteSlot)              fail("invalid but hasWriteSlot", i);
                for (int k = 0; k < MSHR_MAX_PENDING; ++k)
                    if (e.slots[k].valid)        fail("invalid entry has valid slot", i);
                continue;
            }

            if (e.state == State::IDLE)          fail("valid but IDLE", i);
            if (e.validCnt < 1 || e.validCnt > MSHR_MAX_PENDING)
                                                 fail("validCnt out of range", i);
            if (e.replayCnt < 0 || e.replayCnt > e.validCnt)
                                                 fail("replayCnt out of range", i);
            if (e.allocWay < 0 || e.allocWay >= NUM_WAYS)
                                                 fail("allocWay out of range", i);

            bool anyWrite = false;
            for (int k = 0; k < MSHR_MAX_PENDING; ++k) {
                const bool should = (k < e.validCnt);
                if (e.slots[k].valid != should)  fail("slot valid not contiguous", i);
                if (should && e.slots[k].isWrite) anyWrite = true;
            }
            if (e.hasWriteSlot != anyWrite)      fail("hasWriteSlot mismatch", i);

            // SEND / MISS_WAIT 尚未开始重放
            if ((e.state == State::SEND || e.state == State::MISS_WAIT) &&
                e.replayCnt != 0)
                                                 fail("SEND/MISS_WAIT but replayCnt != 0", i);

            // 不变量：同一条 Cache 行至多一个 Entry
            for (int j = i + 1; j < MSHR_ENTRIES; ++j) {
                const Entry& o = entries_[j];
                if (o.valid && o.tag == e.tag && o.index == e.index)
                                                 fail("duplicate line", i);
            }
        }

        if (sendHoldValid_) {
            if (sendHoldEntry_ < 0 || sendHoldEntry_ >= MSHR_ENTRIES)
                                                 fail("sendHold out of range", 0);
            else if (!entries_[sendHoldEntry_].valid ||
                     entries_[sendHoldEntry_].state != State::SEND)
                                                 fail("sendHold not SEND", sendHoldEntry_);
        }
        if (replayPtr_ < 0 || replayPtr_ >= MSHR_ENTRIES)
                                                 fail("replayPtr out of range", 0);

        return ok;
    }

    // ========== 观测 / 调试 ==========
    const Entry& entry(int i) const { return entries_[i]; }

    bool sendHeld()      const { return sendHoldValid_; }
    int  sendHeldEntry() const { return sendHoldEntry_; }

    static const char* stateName(State s) {
        switch (s) {
            case State::IDLE:      return "IDLE";
            case State::SEND:      return "SEND";
            case State::MISS_WAIT: return "MISS_WAIT";
            case State::FILL:      return "FILL";
        }
        return "?";
    }

    void dump(std::ostream& os = std::cout) const {
        os << "=== MSHR dump ===\n";
        for (int i = 0; i < MSHR_ENTRIES; ++i) {
            const Entry& e = entries_[i];
            os << " entry" << i << " : "
               << (e.valid ? stateName(e.state) : "IDLE")
               << " tag=0x" << std::hex << e.tag << std::dec
               << " idx=" << e.index
               << " way=" << e.allocWay
               << " validCnt=" << e.validCnt
               << " replayCnt=" << e.replayCnt
               << (e.hasWriteSlot ? " W" : " -");
            if (e.wbSlotIdx >= 0) os << " wb=" << e.wbSlotIdx;
            os << "\n";
            if (!e.valid) continue;
            for (int k = 0; k < e.validCnt; ++k) {
                const Slot& s = e.slots[k];
                os << "   slot" << k << " : " << (s.isWrite ? "W" : "R")
                   << " off=" << s.wordOff;
                if (s.isWrite) os << " data=0x" << std::hex << s.wData << std::dec;
                os << " respID=" << s.respID << "\n";
            }
        }
    }

private:
    // ---------- 内部选优 ----------
    int freeEntry() const {
        for (int i = 0; i < MSHR_ENTRIES; ++i)
            if (!entries_[i].valid) return i;
        return -1;
    }

    int pickSend() const {                  // 文档 7.7：低位下标优先
        for (int i = 0; i < MSHR_ENTRIES; ++i)
            if (entries_[i].valid && entries_[i].state == State::SEND) return i;
        return -1;
    }

    int pickFill() const {                  // 文档 7.11：FILL 首拍、尚未填充
        for (int i = 0; i < MSHR_ENTRIES; ++i)
            if (entries_[i].valid && entries_[i].state == State::FILL &&
                !entries_[i].fillDone) return i;
        return -1;
    }

    int pickReplay() const {                // 文档 7.12：条目级轮询
        for (int k = 0; k < MSHR_ENTRIES; ++k) {
            const int i = (replayPtr_ + k) % MSHR_ENTRIES;
            const Entry& e = entries_[i];
            if (e.valid && e.state == State::FILL && e.fillDone &&
                e.replayCnt < e.validCnt)
                return i;
        }
        return -1;
    }

    // ---------- 数据合并（文档 7.9 / 7.11） ----------

    // 全部写 Slot 按到达顺序覆盖到 fillData 上（后者覆盖前者）
    static Line mergedData(const Entry& e) {
        Line l = e.fillData;
        for (int k = 0; k < e.validCnt; ++k)
            if (e.slots[k].valid && e.slots[k].isWrite)
                l[e.slots[k].wordOff] = e.slots[k].wData;
        return l;
    }

    // 读 Slot k 的返回数据：fillData + 该 Slot 之前的同字写（不读 Cache）
    static Word replayReadData(const Entry& e, int k) {
        const int off = e.slots[k].wordOff;
        Word d = e.fillData[off];
        for (int j = 0; j < k; ++j)
            if (e.slots[j].valid && e.slots[j].isWrite &&
                e.slots[j].wordOff == off)
                d = e.slots[j].wData;
        return d;
    }

    // ---------- 状态更新 ----------
    static void initEntry(Entry& e, const AllocReq& r) {
        e.valid      = true;
        e.tag        = r.tag;
        e.index      = r.index;
        e.allocWay   = r.allocWay;
        e.fillData.fill(0);
        for (auto& s : e.slots) s = Slot{};
        e.slots[0]   = Slot{ true, r.isWrite, r.wData, r.wordOff, r.respID };
        e.state      = State::SEND;        // 分配后立即进入 SEND（文档 7.3 / 7.7）
        e.replayCnt  = 0;
        e.validCnt   = 1;
        e.hasWriteSlot = r.isWrite;
        e.wbSlotIdx  = r.wbSlotIdx;
        e.fillDone   = false;
    }

    static void appendSlot(Entry& e, const MergeReq& r) {
        e.slots[e.validCnt] = Slot{ true, r.isWrite, r.wData, r.wordOff, r.respID };
        e.validCnt++;
        e.hasWriteSlot = e.hasWriteSlot || r.isWrite;
    }

    static void releaseEntry(Entry& e) {
        e.valid      = false;
        e.state      = State::IDLE;
        e.replayCnt  = 0;
        e.validCnt   = 0;
        e.hasWriteSlot = false;
        e.wbSlotIdx  = -1;
        e.fillDone   = false;
        for (auto& s : e.slots) s = Slot{};
        // tag/index/allocWay/fillData 留待复用，valid=0 即无效
    }

    // ---------- 地址 / ID ----------
    static Addr blockAddr(Tag t, int idx) {
        return (static_cast<Addr>(t) << (INDEX_WIDTH + OFFSET_WIDTH))
             | (static_cast<Addr>(idx) << OFFSET_WIDTH);
    }
    static int busToEntry(BusId id) {
        return static_cast<int>(id & ((1u << MSHR_ID_WIDTH) - 1u));
    }

    // ---------- 状态 ----------
    std::array<Entry, MSHR_ENTRIES> entries_{};
    bool sendHoldValid_ = false;   // 发送保持寄存器（文档 7.7）
    int  sendHoldEntry_ = -1;
    bool sendPresented_ = false;   // 本拍是否调用过 sendReq()
    bool fillPresented_ = false;   // 本拍是否调用过 fillReq()
    int  replayPtr_     = 0;       // 条目级重放轮询指针（文档 7.12）
};

} // namespace dcache
