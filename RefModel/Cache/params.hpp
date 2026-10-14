// params.hpp
#pragma once
#include <array>
#include <cstdint>
#include <cassert>

namespace dcache {

// =============================================================
// Layer 0 : 类型与参数（文档 3.1 / 3.2 / 3.3 / 5.1）
//
// 本层只放"整个模型共用的常量、类型别名、地址解码辅助"。
// 不涉及任何模块状态、时序、控制流。
// =============================================================
// ----- 辅助函数 -----
// 编译期 log2，只对 2 的幂有效
constexpr int clog2(int v, int acc = 0) {
    return v <= 1 ? acc : clog2(v / 2, acc + 1);
}
// ---------- 3.1 主要参数 ----------
constexpr int NUM_SETS            = 32;   // 组数
constexpr int BLOCK_SIZE          = 64;   // 每行字节数
constexpr int NUM_WAYS            = 4;    // 路数
constexpr int DATA_WIDTH          = 32;   // 字宽（位）
constexpr int ADDR_WIDTH          = 32;   // 物理地址宽度
constexpr int MSHR_ENTRIES        = 4;    // MSHR 条目数
constexpr int MSHR_MAX_PENDING    = 4;    // 每条目最大挂起 Slot 数
constexpr int ID_WIDTH            = 4;   // 暂定为4
constexpr int NUM_BUS_OUTSTANDING = 16;   // 总线最大未完成事务数
constexpr int WBB_ENTRIES         = 4;    // 写回缓冲条目数
constexpr int RESP_QUEUE_DEPTH    = 4;    // 响应队列深度

// ---------- 3.2 派生参数 ----------
constexpr int BYTE_WIDTH        = DATA_WIDTH / 8;
constexpr int WORDS_PER_BLOCK   = BLOCK_SIZE / BYTE_WIDTH;
constexpr int INDEX_WIDTH       = clog2(NUM_SETS);
constexpr int OFFSET_WIDTH      = clog2(BLOCK_SIZE);
constexpr int TAG_WIDTH         = ADDR_WIDTH - OFFSET_WIDTH - INDEX_WIDTH;
constexpr int WORD_OFF_WIDTH    = clog2(WORDS_PER_BLOCK);
constexpr int MSHR_ID_WIDTH     = clog2(MSHR_ENTRIES);
constexpr int BUS_ID_WIDTH      = clog2(NUM_BUS_OUTSTANDING);
constexpr int WBB_ID_WIDTH      = clog2(WBB_ENTRIES);

// ---------- 3.3 参数约束（编译期固化） ----------
static_assert((NUM_SETS  & (NUM_SETS  - 1)) == 0, "NUM_SETS must be power of two");
static_assert((BLOCK_SIZE & (BLOCK_SIZE - 1)) == 0, "BLOCK_SIZE must be power of two");
static_assert((BYTE_WIDTH & (BYTE_WIDTH - 1)) == 0, "BYTE_WIDTH must be power of two");
static_assert(BLOCK_SIZE % BYTE_WIDTH == 0, "BLOCK_SIZE must be integer multiple of BYTE_WIDTH");
static_assert((MSHR_ENTRIES & (MSHR_ENTRIES - 1)) == 0, "MSHR_ENTRIES must be power of two");
static_assert((WBB_ENTRIES  & (WBB_ENTRIES  - 1)) == 0, "WBB_ENTRIES must be power of two");
static_assert(WBB_ENTRIES <= NUM_BUS_OUTSTANDING, "WBB_ENTRIES <= NUM_BUS_OUTSTANDING");

// ---------- 基础类型别名 ----------
using Word   = uint32_t;
using Addr   = uint32_t;
using Tag    = uint32_t;
using CpuId  = uint32_t;   // 外部提供，Cache 只透传（文档 4.5）
using BusId  = uint32_t;   // 总线 ID，零扩展后的 MSHR / WBB 位次

// 一行数据：整行宽度 = WORDS_PER_BLOCK × DATA_WIDTH
using Line  = std::array<Word, WORDS_PER_BLOCK>;

// 数据体最小单元：每个 (way, wordOff) 是一个 bank，深度 NUM_SETS
using DataBank = std::array<Word, NUM_SETS>;

// ---------- 5.1 地址分解 ----------
// 布局 : [ tag(21) | index(5) | wordOff(4) | byte(2) ]
constexpr Addr INDEX_MASK    = (1u << INDEX_WIDTH)    - 1u;
constexpr Addr WORD_OFF_MASK = (1u << WORD_OFF_WIDTH) - 1u;
constexpr Addr OFFSET_MASK   = (1u << OFFSET_WIDTH)   - 1u;

inline int  decodeIndex  (Addr a) { return static_cast<int>((a >> OFFSET_WIDTH) & INDEX_MASK);   }
inline int  decodeWordOff(Addr a) { return static_cast<int>((a >> 2)             & WORD_OFF_MASK); }
inline Tag  decodeTag    (Addr a) { return a >> (OFFSET_WIDTH + INDEX_WIDTH);                    }
inline Addr toBlockAddr  (Addr a) { return a & ~OFFSET_MASK;                                     }

// ---------- 4.5 ID 位宽映射（零扩展 / 截取） ----------
// inline BusId  mshr_id_to_bus (int mshrIdx) { return static_cast<BusId>(mshrIdx); }  // 零扩展
// inline BusId  wbb_id_to_bus  (int wbbIdx)  { return static_cast<BusId>(wbbIdx); }  // 零扩展
// inline int    bus_id_to_mshr (BusId id)    { return static_cast<int>(id & ((1u << MSHR_ID_WIDTH) - 1u)); }
// inline int    bus_id_to_wbb  (BusId id)    { return static_cast<int>(id & ((1u << WBB_ID_WIDTH ) - 1u)); }

} // namespace dcache