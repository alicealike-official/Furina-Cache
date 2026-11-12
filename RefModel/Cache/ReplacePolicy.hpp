// ReplacePolicy.hpp
#pragma once
#include "params.hpp"
#include <array>
#include <deque>

namespace dcache {

// =============================================================
// 可插拔替换策略（文档 §10.1 - §10.5）
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
//   2) 否则在本策略**自身的偏好顺序**中，**先剔除被 Way Lock 锁定的路**，
//      再取剩余顺序中最靠前的一路（即"最该被替换且当前可用"的那一路）；
//   3) 若全部路都被锁定 -> 返回 -1（本请求不可接收）。
//
// 注意 (2) 的措辞：剔除锁定项后不能再退化为"按 way 编号顺序向后扫描"。
// 例如 FIFO/LRU 的顺序队列为 [2,0,3,1] 且 way2 被锁时，候选是 way0
// （次老），而不是按编号紧接着的 way3。
//
// 策略本身不修改 valid/locked，这两个数组每拍由调用方传入，
// 因此 getVictim 是纯函数，淘汰被中止时不会破坏策略状态。
//
// 契约触发点（§10.3）：
//   onHit  在 Stage2 命中提交那一拍触发（参数为命中的 set 与 way）；
//   onFill 在填充写 Cache 那一拍触发（参数为 set 与 allocWay）。
//
// 已提供：FifoPolicy（默认）、LruPolicy、PlruPolicy。
// 随机策略留待后续（§14 第二项）。
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

    // 按队列顺序找第一个 valid 且未锁的路（剔除锁定项，保持年龄序）
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
// Tree-PLRU：每 set 一棵完全二叉树，内部节点 1..N-1（堆式编号），
// 叶子为 way 0..N-1（叶子编号 = N + way）。
//   bit[node] == 0 -> 优先左子树；== 1 -> 优先右子树。
// 访问 way 时，把它到根路径上的每一位都指向"远离该 way"的一侧。
// 复位时所有位为 0，因此初始偏好序为 0,1,...,N-1。
//
// 锁定处理（§10.4 语义 A）：在树的偏好序中**剔除**全部被锁的叶子；
// 若首选子树已无未锁叶子，则回退到同父的另一支，再逐层回退。
// 这等价于"先移除锁定路，再取树偏好序中最靠前的一路"。
// -------------------------------------------------------------
class PlruPolicy {
public:
    PlruPolicy() { reset(); }

    void reset() {
        for (int s = 0; s < NUM_SETS; ++s)
            for (int n = 0; n < NUM_WAYS - 1; ++n)
                bits_[s][n] = false;
    }

    int getVictim(int set,
                  const std::array<bool, NUM_WAYS>& valid,
                  const std::array<bool, NUM_WAYS>& locked) const {
        const int free = policy_detail::lowestFreeWay(valid, locked);
        if (free >= 0) return free;
        return pick(set, locked, 1);      // 全锁时返回 -1
    }

    void onHit(int set, int way) { access(set, way); }

    void onFill(int set, int way) { access(set, way); }

    static const char* name() { return "PLRU"; }

private:
    // 子树中是否还有未被锁定的叶子
    bool subtreeHasUnlocked(const std::array<bool, NUM_WAYS>& locked,
                            int node) const {
        if (node >= NUM_WAYS) return !locked[node - NUM_WAYS];
        return subtreeHasUnlocked(locked, 2 * node) ||
               subtreeHasUnlocked(locked, 2 * node + 1);
    }

    // 在子树 node 中按树偏好序挑第一个未被锁定的叶子；全锁返回 -1
    int pick(int set, const std::array<bool, NUM_WAYS>& locked, int node) const {
        if (node >= NUM_WAYS)
            return locked[node - NUM_WAYS] ? -1 : node - NUM_WAYS;

        const bool goRight = bits_[set][node - 1];
        const int  left     = 2 * node;
        const int  right    = 2 * node + 1;
        const int  first    = goRight ? right : left;
        const int  second   = goRight ? left  : right;

        if (subtreeHasUnlocked(locked, first))
            return pick(set, locked, first);
        return pick(set, locked, second);
    }

    // 访问 way：路径上的每一位都指向"远离该 way"的一侧
    void access(int set, int way) {
        int node = NUM_WAYS + way;
        while (node > 1) {
            const int parent = node / 2;
            // 访问的是左孩子(node 偶数) -> 位设为 1（指向右），反之设为 0
            bits_[set][parent - 1] = (node % 2 == 0);
            node = parent;
        }
    }

    std::array<std::array<bool, NUM_WAYS - 1>, NUM_SETS> bits_{};
};

} // namespace dcache
