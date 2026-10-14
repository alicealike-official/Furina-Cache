#ifndef PLRU_REPLACEMENT_HPP
#define PLRU_REPLACEMENT_HPP

#include <vector>
#include <queue>
#include <cmath>
#include <cstdint>
struct PLRUReplacement
{
    // std::vector<unsigned> tree_bit_;
    std::vector<unsigned> tree_bit_;
    unsigned way_bits;
    
    template <typename CacheParamsType>
    PLRUReplacement (const CacheParamsType& params) 
        : tree_bit_(params.num_sets,0),
        way_bits(params.way_index_bits())
    {
        // N个way由N-1个note维护
    }
    
    void on_access(unsigned set_index, unsigned way_index) {
        // 更行tree_bit_
        auto& update_tree_bit = tree_bit_[set_index];
        // for (int i; i<way_bits-1, i++) {
        //     unsigned update_tree_index = (1<<i-1)+(way_index>>(way_bits-i));
        //     update_tree_bit
        // }
        unsigned node = 0;
        for (int level = 0; level < way_bits; level++) {
            // 根据 way_index 的对应位决定去左还是去右，计算下一个 node 索引
            bool go_right = (way_index >> (way_bits - 1 - level)) & 1;
            // 翻转当前节点（PLRU 常用策略：命中某侧时，该节点位取反）
            update_tree_bit ^= (1ULL << node);
            node = (node << 1) | (go_right ? 2 : 1);
        }
        return;
    }

    
    template <typename CacheLineType>
    unsigned get_victim (unsigned index, const std::vector<CacheLineType>& cache_set) {
        auto& fifo_q = fifo_queues_[index];

        // search for empty line
        for (unsigned i=0; i<cache_set.size(); i++) {
            if (!cache_set[i].valid) {
                fifo_q.push(i);
                return i;
            }
        }

        // if no empty lines
        unsigned int victim = fifo_q.front(); // the line head is the oldest way
        fifo_q.pop();
        fifo_q.push(victim); // victim is the yongest way
        return victim;
    }
};

#endif