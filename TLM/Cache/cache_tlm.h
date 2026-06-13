#ifndef CACHE_H
#define CACHE_H

#include <systemc>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <vector>
#include <cstdint>
#include <cassert>

enum class WritePolicy {
    WRITE_BACK,
    WRITE_THROUGH
};

enum class ReplacePolicy {
    FIFO
};


struct CacheParams
{
    unsigned int num_sets;
    unsigned int num_ways;
    unsigned int line_size;
    
    WritePolicy write_plc       = WritePolicy::WRITE_BACK;
    ReplacePolicy replace_plc   = ReplacePolicy::FIFO;

    double miss_latency = 10.0;
    double hit_latency  = 1.0;

    unsigned int set_index_bits() const {
        return static_cast<unsigned int>(std::log2(num_sets)); 
    }

    unsigned int offset_index_bits() const {
        return static_cast<unsigned int>(std::log2(line_size)); 
    }

    unsigned int gen_offset_mask() const {
        return (line_size-1);
    }

    unsigned int gen_index_mask() const {
        return ((num_sets-1)<<offset_index_bits());
    }

    
    // unsigned int way_index_bits() const {
    //     return static_cast<unsigned int>(std::log2(num_ways));
    // }


    //初始化结构体
    CacheParams(unsigned int sets, unsigned int ways, unsigned int line_sz) :
        num_sets(sets),
        num_ways(ways),
        line_size(line_sz) {
            assert((sets & (sets-1)) == 0);
            assert((line_sz & (line_sz-1)) == 0);
        }
};



class Cache_tlm_model : public sc_core::sc_module {
public: 
    tlm_utils::simple_target_socket<Cache_tlm_model> cpu_socket;
    tlm_utils::simple_initiator_socket<Cache_tlm_model> mem_socket;

    //构造函数
    Cache_tlm_model(
        sc_core::sc_module_name name,
        conset CacheParams& params
    );
    ~Cache_tlm_model();//delete

    void b_transport(
        tlm::tlm_generic_payload& trans,
        sc_core::sc_time& delay
    );

private:
    CacheParams params_;
    struct CacheLine {
        sc_dt::sc_bit valid;
        sc_dt::sc_bit dirty;
        uint64_t tag;
        unsigned char* data;
        CacheLine() : valid('0'), dirty('0'), tag(0), data(nullptr) {}
    };

    // std::vector<CacheLine> line_;
    std::vector<std::vector<CacheLine>> sets_; //用于存放CacheLine动态数组的动态数组


    //TODO
    // internal proc function
    void handle_request(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);
    void read_miss_proc(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay,
                        unsigned int index, unsigned int tag, unsigned int offset);
    
    void write_miss_proc(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay,
                        unsigned int index, unsigned int tag, unsigned int offset);
    
    void write_back(unsigned int index);
    void fill_line();
};


#endif