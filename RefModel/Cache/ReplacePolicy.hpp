// ReplacePolicy.hpp
#pragma once
#include "params.hpp"
#include <array>
#include <deque>

namespace dcache {

// =============================================================
// 可插拔替换策略（文档 §10.1 - §10.4）
//
// 策略以**模板参数**的形式注入 CacheTop（见 CacheTopT<Policy>），
// 采用 duck typing、无虚函数，编译期即可选定算法。
//
// 策略需要实现下面四个成员（Policy Concept）：
//
//   void reset();
//   int  getVictim(int set,
//                  const std::array<bool, NUM_WAYS>& valid,
//                  const std::array<bool, NUM_WAYS>& locked) const;
//   void onHit (int set, int way);
//   void onFill(int set, int way);
//
// getVictim 的契约（§10.4，所有策略共用）：
//   1) 优先返回 "valid=0 且未锁" 的路（低下标优先）；
//   2) 否则按本策略的顺序给出一个 "valid 且未锁" 的候选；
//   3) 若全部路都被 Way Lock 锁定 -> 返回 -1（本请求不可接收）。
// 注意：策略本身**不**感知 valid/locked，这两个数组由调用方每拍传入，
// 因此 getVictim 是纯函数，淘汰被中止时不会破坏策略状态。
//
// 契约触发点（§10.3）：
//   onHit  在 Stage2 命中提交那一拍触发（参数为命中的 set 与 way）；
//   onFill 在填充写 Cache 那一拍触发（参数为 set 与 allocWay）。
//
// 已提供：FifoPolicy（默认）、LruPolicy、RoundRobinPolicy。
// 随机 / PLRU 留待后续（§14 第二项）。
// =============================================================

namespace policy_detail {

// §10.4 第 1 步：优先 "valid=0 且未锁"，低下标优先。
inline int lowestFreeWay(const std::array<bool, NUM_WAYS>& valid,
                         const std::array<bool, NUM_WAYS>& locked) {
    for (int w = 0; w < NUM_WAYS; ++w)
        if (!valid[w] && !locked[w]) return w;
    return -1;
}

} // namespace policy_detail

// -------------------------------------------------------------
// 顺序队列基类：每个 set 一个 way 顺序队列，队首为最老
// -------------------------------------------------------------
class OrderedPolicyBase {
public:
    void reset() {
        for (int s = 0; s < NUM_SETS; ++s) {
            order_[s].clear();
            for (int w = 0; w < NUM_WAYS; ++w)
                order_[s].push_back(w);
        }
    }

protected:
    OrderedPolicyBase() { reset(); }

    // 按队列顺序找第一个 valid 且未锁的路
    int orderedCandidate(int set,
                         const std::array<bool, NUM_WAYS>& valid,
                         const std::array<bool, NUM_WAYS>& locked) const {
        for (int w : order_[set])
            if (valid[w] && !locked[w]) return w;
        return -1;
    }

    // 把 way 移到队尾（成为最新）
    void touch(int set, int way) {
        auto& q = order_[set];
        for (auto it = q.begin(); it != q.end(); ++it) {
            if (*it == way) {
                q.erase(it);
                break;
            }
        }
        q.push_back(way);
    }

    std::array<std::deque<int>, NUM_SETS> order_;
};

// -------------------------------------------------------------
// FIFO：命中不改变顺序，填充时把该路移到队尾
// -------------------------------------------------------------
class FifoPolicy : public OrderedPolicyBase {
public:
    int getVictim(int set,
                  const std::array<bool, NUM_WAYS>& valid,
                  const std::array<bool, NUM_WAYS>& locked) const {
        const int free = policy_detail::lowestFreeWay(valid, locked);
        if (free >= 0) return free;
        return orderedCandidate(set, valid, locked);
    }

    void onHit(int /*set*/, int /*way*/) {}

    void onFill(int set, int way) { touch(set, way); }

    static const char* name() { return "FIFO"; }
};

// -------------------------------------------------------------
// LRU：命中与填充都把该路移到队尾（队首 = 最久未使用）
// -------------------------------------------------------------
class LruPolicy : public OrderedPolicyBase {
public:
    int getVictim(int set,
                  const std::array<bool, NUM_WAYS>& valid,
                  const std::array<bool, NUM_WAYS>& locked) const {
        const int free = policy_detail::lowestFreeWay(valid, locked);
        if (free >= 0) return free;
        return orderedCandidate(set, valid, locked);
    }

    void onHit(int set, int way) { touch(set, way); }

    void onFill(int set, int way) { touch(set, way); }

    static const char* name() { return "LRU"; }
};

// -------------------------------------------------------------
// RoundRobin：每个 set 一个指针，候选从指针处向后扫描；
// 填充后指针移到被填充路的下一路。
// -------------------------------------------------------------
class RoundRobinPolicy {
public:
    RoundRobinPolicy() { reset(); }

    void reset() {
        for (int s = 0; s < NUM_SETS; ++s) ptr_[s] = 0;
    }

    int getVictim(int set,
                  const std::array<bool, NUM_WAYS>& valid,
                  const std::array<bool, NUM_WAYS>& locked) const {
        const int free = policy_detail::lowestFreeWay(valid, locked);
        if (free >= 0) return free;
        for (int k = 0; k < NUM_WAYS; ++k) {
            const int w = (ptr_[set] + k) % NUM_WAYS;
            if (valid[w] && !locked[w]) return w;
        }
        return -1;
    }

    void onHit(int /*set*/, int /*way*/) {}

    void onFill(int set, int way) { ptr_[set] = (way + 1) % NUM_WAYS; }

    static const char* name() { return "RR"; }

private:
    std::array<int, NUM_SETS> ptr_{};
};

} // namespace dcache
