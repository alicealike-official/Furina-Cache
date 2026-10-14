#ifndef FIFO_REPLACEMENT_HPP
#define FIFO_REPLACEMENT_HPP

#include <vector>
#include <queue>
struct FIFOReplacement
{
    std::vector<std::queue<unsigned>> fifo_queues_;
    
    template <typename CacheParamsType>
    FIFOReplacement (const CacheParamsType& params) 
        : fifo_queues_(params.num_sets)
    {}

    void on_access(unsigned set_index, unsigned way_index) {
        // 更新tree_bit_
        // FIFO留空
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