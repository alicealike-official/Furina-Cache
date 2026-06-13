// simple_cache.h
#ifndef SIMPLE_CACHE_H
#define SIMPLE_CACHE_H

#include <systemc>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h> 
#include <tlm_utils/simple_initiator_socket.h>
#include <vector>

class SimpleCache : public sc_core::sc_module {
public:
    // 面向CPU的target socket，接收读写请求
    tlm_utils::simple_target_socket<SimpleCache> cpu_socket;
    // 面向内存的initiator socket，发出读写事务
    tlm_utils::simple_initiator_socket<SimpleCache> mem_socket;

    // 构造函数
    // num_lines: 缓存行数（须为2的幂）
    // line_size: 每行字节数（须为2的幂）
    SimpleCache(sc_core::sc_module_name name, unsigned num_lines, unsigned line_size);
    ~SimpleCache();

    // TLM2.0阻塞传输入口
    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);

private:
    struct CacheLine {
        bool valid;
        bool dirty;
        uint64_t tag;
        unsigned char* data; // 行数据存储
        CacheLine() : valid(false), dirty(false), tag(0), data(nullptr) {}
    };

    unsigned num_lines_;
    unsigned line_size_;
    unsigned index_bits_;
    unsigned offset_bits_;
    unsigned index_mask_;
    unsigned offset_mask_;
    std::vector<CacheLine> lines_;

    // 内部处理函数
    void handle_request(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);
    void read_miss(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay,
                   unsigned index, uint64_t tag, unsigned offset);
    void write_miss(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay,
                    unsigned index, uint64_t tag, unsigned offset);
    void write_back(unsigned index);
    void fill_line(unsigned index, uint64_t tag, const unsigned char* data);
};

#endif // SIMPLE_CACHE_H