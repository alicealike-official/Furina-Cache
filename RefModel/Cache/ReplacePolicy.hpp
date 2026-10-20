// ReplacePolicy.hpp
#pragma once
#include "params.hpp"
#include <array>
#include <deque>

namespace dcache {

// =============================================================
// FIFO 替换策略（参考旧模型 fifo_policy.hpp 的设计）
//
// - 每个 set 维护一个 way 的顺序队列，队首为"最老"
// - victim 选择：
//     1) 优先选"valid=0 且未锁"的路；
//     2) 否则按 FIFO 顺序选第一个"valid 且未锁"的路；
//     3) 全被锁 -> -1（请求不可接收）
// - onHit ：FIFO 不改变顺序（空实现）
// - onFill：把该路移到队尾（成为最新）
//
// 文档依据：§10.1 - §10.4
// 注意：getVictim() 是纯函数（不弹队列），
//       淘汰被中止时不会破坏 FIFO 状态。
// =============================================================
class FifoPolicy {
public:
    FifoPolicy() { reset(); }

    void reset() {
        for (int s = 0; s < NUM_SETS; ++s) {
            order_[s].clear();
            for (int w = 0; w < NUM_WAYS; ++w)
                order_[s].push_back(w);
        }
    }

    // valid / locked 由调用方按 way 给出
    int getVictim(int set,
                  const std::array<bool, NUM_WAYS>& valid,
                  const std::array<bool, NUM_WAYS>& locked) const {
        // 1) 优先空且未锁
        for (int w = 0; w < NUM_WAYS; ++w)
            if (!valid[w] && !locked[w]) return w;

        // 2) 按 FIFO 顺序找第一个 valid 且未锁
        for (int w : order_[set])
            if (valid[w] && !locked[w]) return w;

        // 3) 全部被锁
        return -1;
    }

    void onHit(int /*set*/, int /*way*/) {}

    void onFill(int set, int way) {
        auto& q = order_[set];
        for (auto it = q.begin(); it != q.end(); ++it) {
            if (*it == way) {
                q.erase(it);
                break;
            }
        }
        q.push_back(way);
    }

private:
    std::array<std::deque<int>, NUM_SETS> order_;
};

} // namespace dcache
