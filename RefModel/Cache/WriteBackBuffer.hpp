// WriteBackBuffer.hpp
#pragma once
#include "params.hpp"
#include <array>
#include <cassert>
#include <cstdint>
#include <iomanip>
#include <iostream>

namespace dcache {

// =============================================================
// Layer 1 : WriteBackBuffer 写回缓冲（预留 / 装载 / 异步写回）
//
// 对应文档 8.1 - 8.8、12.5、13（不变量三、六）。
//
// 时序约定（松散时序），与 CacheMem 对齐：
//   - 每拍分两步：
//       (1) 外部布置 *_req 字段，并读取"组合输出"
//       (2) 调用 tick()，表示本拍时钟沿
//   - tick() 内的一切状态更新都基于"本拍开始时的状态"求值，
//     等价于硬件的"组合求值 -> 沿上更新"。
//
// 为什么预留与发送是"组合输出"而非"tick 后输出"：
//   文档 12.3 要求淘汰原子组（Way Lock + WBB 预留+写 addr +
//   清 valid + 分配 MSHR + 读 victim 整行）的全部使能条件在
//   Stage2 当拍组合可知，且整组"全做或全不做"（文档 8.4）。
//   因此"预留能否成功、选中哪个槽位"必须在 tick() 之前读到；
//   发送仲裁（文档 8.6）同理。
//
// 端口模型：
//   上游（淘汰路径）: rsv_req（预留+写 addr） / push_req（写整行 data）
//   下游（内存写）  : sendReq() 组合输出 + mem_wr_ready / mem_wr_resp
//                     （WBB 内部轮询自主驱动，文档 8.6）
//   查询（给 Stage1 检查 / Stage2 重查）: full() / hasSameAddr()
//
// 本层明确不做（属于 Layer 2 / Layer 3）：
//   victim 选择、清 victim valid、Way Lock、MSHR 分配、Stage2 冻结、
//   cpuReady 反压合成。
// =============================================================

// 可关闭的断言：release（NDEBUG）下编译为空
#ifndef DCACHE_WBB_ASSERT
#  if defined(NDEBUG)
#    define DCACHE_WBB_ASSERT(x) ((void)0)
#  else
#    define DCACHE_WBB_ASSERT(x) assert(x)
#  endif
#endif

class WriteBackBuffer {
public:
    // ---------- 端口请求 / 响应 ----------

    // ----- 上游 Rsv：预留一个槽位并写入 victim 地址（文档 8.3 / 8.4） -----
    // 预留当拍即写入 addr，使 hasSameAddr() 从下一拍起即可命中（文档 8.7）。
    struct RsvReq {
        bool en   = false;
        Addr addr = 0;   // victim 的块对齐地址（toBlockAddr 归一）
    };
    struct RsvResp {
        // reserve():      ok = 当前是否存在空闲槽（与 rsv_req.en 无关）
        // reserve(en):    ok = 本次预留是否成功（= en && 有空槽）
        bool ok   = false;
        int  slot = -1;      // 成功时选中的槽位下标
    };

    // ----- 上游 Push：把 victim 整行装载进已预留槽位（文档 8.3） -----
    struct PushReq {
        bool en   = false;
        int  slot = 0;      // 取自上拍 RsvResp.slot
        Line line{};        // victim 整行（来自 CacheMem 的 R2）
    };

    // ----- 下游 MemWr：向内存发起写回（文档 4.2 / 4.5 / 8.6 / 11.6） -----
    struct MemWrReq {
        bool  en   = false;  // 有一个 valid 且未发出的条目
        Addr  addr = 0;      // 块对齐
        Line  data{};        // 整行
        BusId id   = 0;      // = 槽位下标零扩展到总线 ID 宽度（文档 4.5）
    };
    struct MemWrResp {       // 从端输入：内存写完成
        bool  en = false;
        BusId id = 0;        // 低位索引槽位；高位非 0 属【待解决】，此处不处理
    };

    // ---------- 端口输入（由驱动方每拍布置） ----------
    RsvReq    rsv_req;
    PushReq   push_req;
    bool      mem_wr_ready = false;   // 内存写通道握手 ready（无背压时可恒真）
    MemWrResp mem_wr_resp;            // 内存写完成响应

    // ---------- 构造 / 复位（文档 5.6：WBB 视为空） ----------
    WriteBackBuffer() { reset(); }

    void reset() {
        for (int i = 0; i < WBB_ENTRIES; ++i) {
            valid_ [i] = false;
            resv_  [i] = false;
            issued_[i] = false;
            addr_  [i] = 0;
            data_  [i].fill(0);
        }
        rrPtr_ = 0;
        rsv_req      = RsvReq{};
        push_req     = PushReq{};
        mem_wr_ready = false;
        mem_wr_resp  = MemWrResp{};
    }

    // ========== 组合输出（tick 之前读取；纯函数，不改状态） ==========

    // 预留探测：当前是否存在空闲槽（文档 8.4 / 8.8：占用 = valid || reserved）
    // 注意：reserveOk() 只回答"有没有空槽"，不回答"你这次预留是否成功"。
    bool reserveOk()   const { return reserveSlot() >= 0; }
    int  reserveSlot() const {
        for (int i = 0; i < WBB_ENTRIES; ++i)
            if (!valid_[i] && !resv_[i]) return i;
        return -1;
    }
    // 与 RsvReq 配对的组合结果。
    // 【注意】ok 仅表示"当前存在空闲槽"，与 rsv_req.en 无关；
    //   真正的"本次预留成功" = rsv_req.en && reserve().ok
    //   （tick() 内部正是这样判定的）。
    //   若想一步得到"带 en 的结论"，请用下面的 reserve(bool) 重载。
    RsvResp reserve() const { return RsvResp{ reserveOk(), reserveSlot() }; }

    // 带 en 的版本：返回值直接表示"本次预留是否成功"。
    //   en = false 时不探测，返回 {ok=false, slot=-1}。
    //   en = true  时等价于 reserve()，但 ok 已与 en 相与。
    RsvResp reserve(bool en) const {
        if (!en) return RsvResp{};
        const int s = reserveSlot();
        return RsvResp{ s >= 0, s };
    }

    // 发送仲裁：轮询选出 valid && !issued 的条目（文档 8.6）
    MemWrReq sendReq() const {
        MemWrReq r;
        for (int k = 0; k < WBB_ENTRIES; ++k) {
            const int i = (rrPtr_ + k) % WBB_ENTRIES;
            if (valid_[i] && !issued_[i]) {
                r.en   = true;
                r.id   = static_cast<BusId>(i);   // 零扩展（文档 4.5）
                r.addr = addr_[i];
                r.data = data_[i];
                break;
            }
        }
        return r;
    }

    // 满：所有槽位均被占用（valid || reserved）（文档 8.8 / 11.1）
    bool full() const {
        for (int i = 0; i < WBB_ENTRIES; ++i)
            if (!valid_[i] && !resv_[i]) return false;
        return true;
    }

    // 同地址检查：必须覆盖 valid 与 reserved（文档 8.7 / 11.1 / 11.2）
    bool hasSameAddr(Addr a) const {
        for (int i = 0; i < WBB_ENTRIES; ++i)
            if ((valid_[i] || resv_[i]) && addr_[i] == a) return true;
        return false;
    }

    // ========== 一拍 ==========
    void tick() {
        // ---- 1) 组合求值：全部基于"本拍开始时"的状态 ----
        const RsvResp  rsv   = reserve(rsv_req.en);   // 带 en：ok 即"本次预留是否成功"
        const int      rSlot = rsv.slot;
        const bool     rOk   = rsv.ok;
        const MemWrReq sReq  = sendReq();
        const bool     sFire = (sReq.en && mem_wr_ready);

        // ---- 2) 沿上更新 ----

        // (a) 释放：内存写响应 -> 清 valid（文档 8.3；ID 不释放）
        if (mem_wr_resp.en) {
            const int i = static_cast<int>(mem_wr_resp.id & ((1u << WBB_ID_WIDTH) - 1u));
            if (0 <= i && i < WBB_ENTRIES) {
                valid_[i] = false;
                issued_[i] = false;
                resv_[i]  = false;
            }
        }

        // (b) 发出：与内存握手成功 -> 置 issued，轮询指针前移（文档 8.6）
        if (sFire) {
            issued_[sReq.id] = true;
            rrPtr_ = (static_cast<int>(sReq.id) + 1) % WBB_ENTRIES;
        }

        // (c) 装载：push 整行数据 -> 置 valid、清 reserved（文档 8.3）
        if (push_req.en) {
            DCACHE_WBB_ASSERT(0 <= push_req.slot && push_req.slot < WBB_ENTRIES);
            // 不变量六：push 必须落在"已预留"的槽位（清 valid 前必须已预留）
            DCACHE_WBB_ASSERT(resv_[push_req.slot]);
            const int i = push_req.slot;
            data_ [i] = push_req.line;
            valid_[i] = true;
            resv_ [i] = false;
        }

        // (d) 预留：写 addr、置 reserved，valid 保持 0（文档 8.3 / 8.4）
        if (rsv_req.en)
            DCACHE_WBB_ASSERT(rsv_req.addr == toBlockAddr(rsv_req.addr));  // 块对齐
        if (rOk) {
            addr_[rSlot] = rsv_req.addr;
            resv_[rSlot] = true;
        }

        // ---- 3) 不变量自检（文档 13 第三、六条） ----
        DCACHE_WBB_ASSERT(checkInvariants());
    }

    // ========== 不变量自检（文档 13 第三、六条） ==========
    // 不变量三：同一地址至多存在一个条目（含 reserved）
    // 状态一致性：issued 蕴含 valid；reserved 与 valid 互斥
    bool checkInvariants(std::ostream* err = nullptr) const {
        bool ok = true;
        auto fail = [&](const char* m, int i) {
            ok = false;
            if (err) *err << "[WBB invariant] slot" << i << ": " << m << "\n";
        };
        for (int i = 0; i < WBB_ENTRIES; ++i) {
            if (issued_[i] && !valid_[i]) fail("issued but not valid", i);
            if (resv_[i]   &&  valid_[i]) fail("reserved && valid (互斥)", i);
            if (resv_[i] || valid_[i])
                for (int j = i + 1; j < WBB_ENTRIES; ++j)
                    if ((resv_[j] || valid_[j]) && addr_[j] == addr_[i])
                        fail("duplicate addr（不变量三）", i);
        }
        return ok;
    }

    // ========== 观测 / 预置（调试、单测用；绕过端口） ==========
    bool getValid   (int i) const { return valid_ [i]; }
    bool getReserved(int i) const { return resv_  [i]; }
    bool getIssued  (int i) const { return issued_[i]; }
    Addr getAddr    (int i) const { return addr_  [i]; }
    Word getWord    (int i, int o) const { return data_[i][o]; }

    void pokeValid   (int i, bool v)        { valid_ [i] = v; }
    void pokeReserved(int i, bool v)        { resv_  [i] = v; }
    void pokeIssued  (int i, bool v)        { issued_[i] = v; }
    void pokeAddr    (int i, Addr a)        { addr_  [i] = a; }
    void pokeWord    (int i, int o, Word d) { data_[i][o] = d; }

    void dump(std::ostream& os = std::cout) const {
        os << "=== WriteBackBuffer dump ===\n";
        for (int i = 0; i < WBB_ENTRIES; ++i) {
            os << " slot" << i << " : "
               << (valid_[i] ? "V" : (resv_[i] ? "R" : "-"))
               << (issued_[i] ? " I" : "  ")
               << " addr=0x" << std::hex << addr_[i] << std::dec << " : ";
            if (valid_[i]) {
                for (int o = 0; o < WORDS_PER_BLOCK; ++o)
                    os << std::hex << std::setw(8) << std::setfill('0')
                       << data_[i][o] << " ";
            } else {
                os << "(data not yet pushed)";
            }
            os << std::dec << "\n";
        }
    }

private:
    bool valid_ [WBB_ENTRIES];   // 已装载有效数据（文档 8.2）
    bool resv_  [WBB_ENTRIES];   // 已被预留、数据尚未写入（文档 8.2）
    bool issued_[WBB_ENTRIES];   // 是否已向内存发出写回请求（文档 8.2）
    Addr addr_  [WBB_ENTRIES];   // 写回地址（块对齐）
    Line data_  [WBB_ENTRIES];   // 整行数据
    int  rrPtr_ = 0;             // 发送轮询指针（文档 8.6）
};

} // namespace dcache
