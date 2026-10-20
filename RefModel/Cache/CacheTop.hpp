// CacheTop.hpp
#pragma once
#include "params.hpp"
#include "CacheMem.hpp"
#include "MSHR.hpp"
#include "WriteBackBuffer.hpp"
#include "ReplacePolicy.hpp"

#include <array>
#include <cassert>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <iostream>

namespace dcache {

// =============================================================
// Layer 2 : CacheTop 顶层组装
//
// 对应文档：§2、§6、§9、§10、§11、§12、§13
//
// 组成：
//   - Stage1 / Stage2 两级流水 + 命中判断
//   - CacheMem（存储体）
//   - MSHR（未命中 / 合并 / 填充 / 重放）
//   - WriteBackBuffer（脏行写回）
//   - 读 / 写响应队列
//   - Way Lock 表 + FifoPolicy
//
// 时序约定（与三个 Layer 1 模块一致）：
//   1) 布置输入，调用 eval() 观察组合输出
//   2) 调用 tick() 推进时钟沿（tick 内部会再 eval 一次，幂等）
//
//   bool ok = top.cpu_ready;   // eval() 之后有效
//   top.tick();
//
// 说明：
//   - cpu_ready / 响应 valid / 内存请求 valid 都是"本拍组合输出"
//   - tick() 之后这些字段仍保留本拍的值；下一拍前请重新 eval()
// =============================================================

class CacheTop {
public:
    // ---------- 响应队列条目 ----------
    struct ReadResp  { Word rData = 0; CpuId id = 0; };
    struct WriteResp { CpuId id = 0; };

    // ================= 公共输入 =================
    // CPU 请求
    bool  cpu_valid = false;
    Addr  cpu_addr  = 0;
    bool  cpu_wrEn  = false;
    Word  cpu_wData = 0;
    CpuId cpu_id    = 0;

    // CPU 响应反压
    bool  cpuReadResp_ready  = false;
    bool  cpuWriteResp_ready = false;

    // 内存侧
    bool  memReadReq_ready   = false;
    bool  memReadResp_valid  = false;
    Line  memReadResp_line{};
    BusId memReadResp_id     = 0;

    bool  memWriteReq_ready  = false;
    bool  memWriteResp_valid = false;
    BusId memWriteResp_id    = 0;

    // ================= 公共输出 =================
    bool  cpu_ready = false;

    bool  cpuReadResp_valid = false;
    Word  cpuReadResp_rData = 0;
    CpuId cpuReadResp_id    = 0;

    bool  cpuWriteResp_valid = false;
    CpuId cpuWriteResp_id    = 0;

    bool  memReadReq_valid = false;
    Addr  memReadReq_addr  = 0;
    BusId memReadReq_id    = 0;

    bool  memWriteReq_valid = false;
    Addr  memWriteReq_addr  = 0;
    BusId memWriteReq_id    = 0;
    Line  memWriteReq_line{};

    // ================= 构造 / 复位 =================
    CacheTop() { reset(); }

    void reset() {
        cache_.reset();
        mshr_.reset();
        wbb_.reset();
        policy_.reset();

        for (int w = 0; w < NUM_WAYS; ++w)
            for (int s = 0; s < NUM_SETS; ++s)
                locked_[w][s] = false;

        readQ_.clear();
        writeQ_.clear();

        s2Valid_ = false;
        s2Tag_ = 0; s2Index_ = 0; s2WordOff_ = 0; s2BlockAddr_ = 0;
        s2WrEn_ = false; s2WData_ = 0; s2Id_ = 0;

        prevW1Valid_ = false; prevW1Set_ = 0; prevW1Way_ = 0;
        prevW1WordOff_ = 0; prevW1Data_ = 0;

        pushPending_ = false; pushSlot_ = -1;

        // 输入
        cpu_valid = false; cpu_addr = 0; cpu_wrEn = false; cpu_wData = 0; cpu_id = 0;
        cpuReadResp_ready = false; cpuWriteResp_ready = false;
        memReadReq_ready = false; memReadResp_valid = false;
        memReadResp_line.fill(0); memReadResp_id = 0;
        memWriteReq_ready = false; memWriteResp_valid = false; memWriteResp_id = 0;

        // 输出
        cpu_ready = false;
        cpuReadResp_valid = false; cpuReadResp_rData = 0; cpuReadResp_id = 0;
        cpuWriteResp_valid = false; cpuWriteResp_id = 0;
        memReadReq_valid = false; memReadReq_addr = 0; memReadReq_id = 0;
        memWriteReq_valid = false; memWriteReq_addr = 0; memWriteReq_id = 0;
        memWriteReq_line.fill(0);

        // 组合中间量
        hit_ = false; hitWay_ = -1;
        hitInMshr2_ = false; canMerge2_ = false;
        needEvict_ = false; victimWay_ = -1; victimDirty_ = false;
        victimTag_ = 0; victimBlockAddr_ = 0;
        rsvOk_ = true; rsvSlot_ = -1;
        s2Stuck_ = false; s2Commit_ = false;
        commitEvict_ = false; doMerge_ = false;
        hitRead_ = false; hitWrite_ = false;
        hitReadData_ = 0;
        fill_ = MSHR::FillReq{};
        replay_ = MSHR::ReplayReq{};
        replayLast_ = false; replayIndex_ = -1; replayWay_ = -1;
        replayPushOk_ = false;
        pushHitRead_ = false; pushHitWrite_ = false;
        pushReplayRead_ = false; pushReplayWrite_ = false;
        s1Fire_ = false;
    }

    // ================= 组合求值 =================
    // 计算本拍所有组合信号，并把请求布置到三个 Layer 1 模块的输入端口。
    // 可多次调用（幂等）；tick() 内部也会调用。
    void eval() {
        // ---------- 0) CPU 地址分解 ----------
        const Tag  cTag  = decodeTag(cpu_addr);
        const int  cIdx  = decodeIndex(cpu_addr);
        const int  cWoff = decodeWordOff(cpu_addr);
        const Addr cBlk  = toBlockAddr(cpu_addr);

        // ---------- 1) Stage2：命中判断 ----------
        hit_ = false; hitWay_ = -1;
        for (int w = 0; w < NUM_WAYS; ++w) {
            if (cache_.r1_resp.valid[w] &&
                cache_.r1_resp.tag[w] == s2Tag_ &&
                !locked(s2Index_, w)) {
                hit_ = true;
                hitWay_ = w;
                break;
            }
        }

        // ---------- 2) Stage2：MSHR 匹配 ----------
        const MSHR::MatchInfo m2 = mshr_.match(s2Tag_, s2Index_);
        hitInMshr2_ = m2.hit;
        canMerge2_  = m2.mergeable && m2.slotFree;

        // ---------- 3) Stage2：victim 选择 / WBB 预留 ----------
        needEvict_ = s2Valid_ && !hit_ && !hitInMshr2_;
        victimWay_ = needEvict_ ? pickVictim(s2Index_) : -1;
        victimDirty_ = (victimWay_ >= 0) && cache_.getDirty(s2Index_, victimWay_);
        victimTag_ = (victimWay_ >= 0) ? cache_.getTag(s2Index_, victimWay_) : 0;
        victimBlockAddr_ = blockAddr(victimTag_, s2Index_);

        const WriteBackBuffer::RsvResp rsv = wbb_.reserve();   // 纯组合
        rsvOk_   = !victimDirty_ || rsv.ok;
        rsvSlot_ = rsv.slot;

        // ---------- 4) Stage2：冻结判定（§11.2） ----------
        const bool respFull2 = respFullFor(s2WrEn_);
        const bool wbSame2   = wbb_.hasSameAddr(s2BlockAddr_);
        const bool hasFree2  = mshr_.hasFree();
        const bool hasWay2   = hasAvailableWay(s2Index_);
        const bool reserveFail = needEvict_ && !rsvOk_;

        s2Stuck_ = s2Valid_ && (
              respFull2
           || (!hit_ && hitInMshr2_ && !canMerge2_)
           || (needEvict_ && (!hasFree2 || !hasWay2))
           || (!hit_ && wbSame2)
           || reserveFail
        );
        s2Commit_ = s2Valid_ && !s2Stuck_;

        // ---------- 5) Stage1：准入（§11.1） ----------
        const MSHR::MatchInfo m1 = mshr_.match(cTag, cIdx);
        const bool canMerge1 = m1.mergeable && m1.slotFree;
        const bool hitMshr1  = m1.hit;
        const bool hasFree1  = mshr_.hasFree();
        const bool wbFull1   = wbb_.full();
        const bool wbSame1   = wbb_.hasSameAddr(cBlk);
        const bool hasWay1   = hasAvailableWay(cIdx);
        const bool respFull1 = respFullFor(cpu_wrEn);

        const bool admissionOk = !respFull1 &&
            (canMerge1 ||
             (!hitMshr1 && hasFree1 && !wbFull1 && !wbSame1 && hasWay1));

        cpu_ready = !s2Stuck_ && admissionOk;
        s1Fire_   = cpu_valid && cpu_ready;

        // ---------- 6) 读端口 R1（冻结期间保持刷新） ----------
        if (s2Stuck_)
            cache_.r1_req = CacheMem::R1Req{ true, s2Index_, s2WordOff_ };
        else if (s1Fire_)
            cache_.r1_req = CacheMem::R1Req{ true, cIdx, cWoff };
        else
            cache_.r1_req = CacheMem::R1Req{};

        // ---------- 7) Stage2 提交动作 ----------
        hitRead_  = s2Commit_ && hit_ && !s2WrEn_;
        hitWrite_ = s2Commit_ && hit_ && s2WrEn_;
        doMerge_  = s2Commit_ && !hit_ && hitInMshr2_ && canMerge2_;
        commitEvict_ = s2Commit_ && needEvict_ && victimWay_ >= 0 && rsvOk_;

        // W1：命中单字写
        cache_.w1_req = CacheMem::W1Req{};
        if (hitWrite_)
            cache_.w1_req = CacheMem::W1Req{
                true, s2Index_, hitWay_, s2WordOff_, s2WData_ };

        // Clear / R2：淘汰原子组（§8.4 / §12.3）
        cache_.clr_req = CacheMem::ClearReq{};
        cache_.r2_req  = CacheMem::R2Req{};
        if (commitEvict_) {
            cache_.clr_req = CacheMem::ClearReq{ true, s2Index_, victimWay_ };
            if (victimDirty_)
                cache_.r2_req = CacheMem::R2Req{ true, s2Index_, victimWay_ };
        }

        // MSHR 分配 / 合并
        mshr_.alloc_req = MSHR::AllocReq{};
        mshr_.merge_req = MSHR::MergeReq{};
        if (commitEvict_) {
            mshr_.alloc_req = MSHR::AllocReq{
                true, s2Tag_, s2Index_, victimWay_, s2WrEn_, s2WData_,
                s2WordOff_, s2Id_, victimDirty_ ? rsvSlot_ : -1 };
        } else if (doMerge_) {
            mshr_.merge_req = MSHR::MergeReq{
                true, m2.entry, s2WrEn_, s2WData_, s2WordOff_, s2Id_ };
        }

        // WBB 预留（仅脏 victim）
        wbb_.rsv_req = WriteBackBuffer::RsvReq{};
        if (commitEvict_ && victimDirty_)
            wbb_.rsv_req = WriteBackBuffer::RsvReq{ true, victimBlockAddr_ };

        // ---------- 8) MSHR 填充 -> W2 ----------
        fill_ = mshr_.fillReq();
        cache_.w2_req = CacheMem::W2Req{};
        if (fill_.en)
            cache_.w2_req = CacheMem::W2Req{
                true, fill_.index, fill_.way, fill_.tag, fill_.dirty, fill_.line };

        // ---------- 9) WBB push（上一拍预留的槽） ----------
        wbb_.push_req = WriteBackBuffer::PushReq{};
        if (pushPending_)
            wbb_.push_req = WriteBackBuffer::PushReq{
                true, pushSlot_, cache_.r2_resp.line };

        // ---------- 10) 内存侧 ----------
        const MSHR::MemRdReq rd = mshr_.sendReq();          // 发送仲裁（锁存）
        memReadReq_valid = rd.en;
        memReadReq_addr  = rd.addr;
        memReadReq_id    = rd.id;
        mshr_.mem_rd_ready = memReadReq_ready;
        mshr_.mem_rd_resp  = MSHR::MemRdResp{
            memReadResp_valid, memReadResp_id, memReadResp_line };

        const WriteBackBuffer::MemWrReq wr = wbb_.sendReq();
        memWriteReq_valid = wr.en;
        memWriteReq_addr  = wr.addr;
        memWriteReq_id    = wr.id;
        memWriteReq_line  = wr.data;
        wbb_.mem_wr_ready = memWriteReq_ready;
        wbb_.mem_wr_resp  = WriteBackBuffer::MemWrResp{
            memWriteResp_valid, memWriteResp_id };

        mshr_.fill_ready = true;

        // ---------- 11) MSHR 重放 + 响应队列 ----------
        replay_ = mshr_.replayReq();
        replayLast_ = false; replayIndex_ = -1; replayWay_ = -1;
        if (replay_.en) {
            const MSHR::Entry& e = mshr_.entry(replay_.entry);
            replayIndex_ = e.index;
            replayWay_   = e.allocWay;
            replayLast_  = (replay_.slot == e.validCnt - 1);
        }

        const bool readQFull  = readQ_.size()  >= RESP_QUEUE_DEPTH;
        const bool writeQFull = writeQ_.size() >= RESP_QUEUE_DEPTH;

        pushHitRead_  = hitRead_  && !readQFull;
        pushHitWrite_ = hitWrite_ && !writeQFull;

        // 同一队列内：命中优先于重放（§6.7 / §9.3）
        pushReplayRead_  = replay_.en && !replay_.isWrite &&
                           !readQFull  && !pushHitRead_;
        pushReplayWrite_ = replay_.en &&  replay_.isWrite &&
                           !writeQFull && !pushHitWrite_;
        replayPushOk_ = pushReplayRead_ || pushReplayWrite_;
        mshr_.replay_ready = replayPushOk_;

        // ---------- 12) 响应输出 ----------
        cpuReadResp_valid = !readQ_.empty();
        if (!readQ_.empty()) {
            cpuReadResp_rData = readQ_.front().rData;
            cpuReadResp_id    = readQ_.front().id;
        }
        cpuWriteResp_valid = !writeQ_.empty();
        if (!writeQ_.empty())
            cpuWriteResp_id = writeQ_.front().id;

        // ---------- 13) 命中读数据 + RAW 旁路（§6.6） ----------
        hitReadData_ = 0;
        if (hitRead_) {
            hitReadData_ = cache_.r1_resp.data[hitWay_];
            if (prevW1Valid_ && prevW1Set_ == s2Index_ &&
                prevW1Way_ == hitWay_ && prevW1WordOff_ == s2WordOff_)
                hitReadData_ = prevW1Data_;
        }
    }

    // ================= 时钟沿 =================
    void tick() {
        eval();   // 确保所有模块输入与组合信号都是本拍的

        // 1) 响应弹出（先弹，允许同拍 push）
        if (cpuReadResp_ready  && !readQ_.empty())  readQ_.pop_front();
        if (cpuWriteResp_ready && !writeQ_.empty()) writeQ_.pop_front();

        // 2) 响应推入（命中优先于重放）
        if (pushHitRead_)
            readQ_.push_back(ReadResp{ hitReadData_, s2Id_ });
        else if (pushReplayRead_)
            readQ_.push_back(ReadResp{ replay_.rData, replay_.respID });

        if (pushHitWrite_)
            writeQ_.push_back(WriteResp{ s2Id_ });
        else if (pushReplayWrite_)
            writeQ_.push_back(WriteResp{ replay_.respID });

        // 3) Way Lock（与 MSHR 条目同生同死）
        if (commitEvict_)
            locked_[victimWay_][s2Index_] = true;
        if (replayPushOk_ && replayLast_)
            locked_[replayWay_][replayIndex_] = false;

        // 4) WBB push 流水：本拍消费旧的，下一拍 push 新预留的
        if (pushPending_) pushPending_ = false;
        if (commitEvict_ && victimDirty_) {
            pushPending_ = true;
            pushSlot_    = rsvSlot_;
        }

        // 5) 替换策略
        if (s2Commit_ && hit_)
            policy_.onHit(s2Index_, hitWay_);
        if (fill_.en)
            policy_.onFill(fill_.index, fill_.way);

        // 6) RAW 旁路寄存器
        if (s2Commit_ && hit_ && s2WrEn_) {
            prevW1Valid_   = true;
            prevW1Set_     = s2Index_;
            prevW1Way_     = hitWay_;
            prevW1WordOff_ = s2WordOff_;
            prevW1Data_    = s2WData_;
        } else {
            prevW1Valid_ = false;
        }

        // 7) 三个 Layer 1 模块的沿
        cache_.tick();
        mshr_.tick();
        wbb_.tick();

        // 8) 两级流水
        if (s2Stuck_) {
            // Stage2 冻结：保持 s2 寄存器
        } else {
            if (s2Valid_) s2Valid_ = false;
            if (s1Fire_) {
                s2Valid_     = true;
                s2Tag_       = decodeTag(cpu_addr);
                s2Index_     = decodeIndex(cpu_addr);
                s2WordOff_   = decodeWordOff(cpu_addr);
                s2BlockAddr_ = toBlockAddr(cpu_addr);
                s2WrEn_      = cpu_wrEn;
                s2WData_     = cpu_wData;
                s2Id_        = cpu_id;
            }
        }
    }

    // ================= 观测 =================
    const CacheMem&       cache() const { return cache_; }
    const MSHR&           mshr()  const { return mshr_;  }
    const WriteBackBuffer& wbb()  const { return wbb_;   }

    bool locked(int set, int way) const { return locked_[way][set]; }

    bool s2Valid() const { return s2Valid_; }

    void dump(std::ostream& os = std::cout) const {
        os << "=== CacheTop dump ===\n";
        os << "cpu_ready=" << cpu_ready
           << " s2Valid=" << s2Valid_
           << " s2Stuck=" << s2Stuck_ << "\n";
        os << "readQ=" << readQ_.size() << " writeQ=" << writeQ_.size() << "\n";
        os << "-- wayLock --\n";
        for (int s = 0; s < NUM_SETS; ++s) {
            bool any = false;
            for (int w = 0; w < NUM_WAYS; ++w) if (locked_[w][s]) any = true;
            if (!any) continue;
            os << " set" << s << " : ";
            for (int w = 0; w < NUM_WAYS; ++w)
                os << (locked_[w][s] ? 'L' : '.');
            os << "\n";
        }
        cache_.dump(os);
        mshr_.dump(os);
        wbb_.dump(os);
    }

private:
    // ---------- 小工具 ----------
    bool respFullFor(bool isWrite) const {
        return isWrite ? (writeQ_.size() >= RESP_QUEUE_DEPTH)
                       : (readQ_.size()  >= RESP_QUEUE_DEPTH);
    }

    bool hasAvailableWay(int set) const {
        std::array<bool, NUM_WAYS> valid{}, lock{};
        for (int w = 0; w < NUM_WAYS; ++w) {
            valid[w] = cache_.getValid(set, w);
            lock[w]  = locked_[w][set];
        }
        return policy_.getVictim(set, valid, lock) >= 0;
    }

    int pickVictim(int set) const {
        std::array<bool, NUM_WAYS> valid{}, lock{};
        for (int w = 0; w < NUM_WAYS; ++w) {
            valid[w] = cache_.getValid(set, w);
            lock[w]  = locked_[w][set];
        }
        return policy_.getVictim(set, valid, lock);
    }

    static Addr blockAddr(Tag t, int idx) {
        return (static_cast<Addr>(t) << (INDEX_WIDTH + OFFSET_WIDTH)) |
               (static_cast<Addr>(idx) << OFFSET_WIDTH);
    }

    // ---------- 子模块 ----------
    CacheMem       cache_;
    MSHR           mshr_;
    WriteBackBuffer wbb_;
    FifoPolicy     policy_;

    // ---------- 状态 ----------
    bool locked_[NUM_WAYS][NUM_SETS]{};

    std::deque<ReadResp>  readQ_;
    std::deque<WriteResp> writeQ_;

    // Stage2 流水寄存器
    bool  s2Valid_ = false;
    Tag   s2Tag_ = 0;
    int   s2Index_ = 0;
    int   s2WordOff_ = 0;
    Addr  s2BlockAddr_ = 0;
    bool  s2WrEn_ = false;
    Word  s2WData_ = 0;
    CpuId s2Id_ = 0;

    // RAW 旁路（上一拍的命中写）
    bool prevW1Valid_ = false;
    int  prevW1Set_ = 0;
    int  prevW1Way_ = 0;
    int  prevW1WordOff_ = 0;
    Word prevW1Data_ = 0;

    // WBB push 流水
    bool pushPending_ = false;
    int  pushSlot_ = -1;

    // ---------- 组合中间量（eval 写入，tick 使用） ----------
    bool  s1Fire_ = false;
    bool  hit_ = false;
    int   hitWay_ = -1;
    bool  hitInMshr2_ = false;
    bool  canMerge2_ = false;
    bool  needEvict_ = false;
    int   victimWay_ = -1;
    bool  victimDirty_ = false;
    Tag   victimTag_ = 0;
    Addr  victimBlockAddr_ = 0;
    bool  rsvOk_ = true;
    int   rsvSlot_ = -1;
    bool  s2Stuck_ = false;
    bool  s2Commit_ = false;
    bool  commitEvict_ = false;
    bool  doMerge_ = false;
    bool  hitRead_ = false;
    bool  hitWrite_ = false;
    Word  hitReadData_ = 0;

    MSHR::FillReq   fill_{};
    MSHR::ReplayReq replay_{};
    bool replayLast_ = false;
    int  replayIndex_ = -1;
    int  replayWay_ = -1;
    bool replayPushOk_ = false;

    bool pushHitRead_ = false;
    bool pushHitWrite_ = false;
    bool pushReplayRead_ = false;
    bool pushReplayWrite_ = false;
};

} // namespace dcache
