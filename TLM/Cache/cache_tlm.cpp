#include "cache_tlm.h"
#include <cstring>
#include <cmath>

//构造函数
Cache_tlm_model::Cache_tlm_model(
    sc_core::sc_module_name name,
    const CacheParams& params) :
    sc_core::sc_module(name),
    cpu_socket("cpu_socket"),
    mem_socket("mem_socket"),
    params_(params),
    sets_(params.num_sets, std::vector<CacheLine>(params.num_ways))
{
    for (auto& set : sets_) {
        for (auto& way : set) {
            way.data = new unsigned char[params_.line_size];
            std::memset(way.data,0,params_.line_size);
        }
    }
}


void Cache_tlm_model::~Cache_tlm_model() {
    for (auto& set : set_) {
        for (auto& way : set) {
            delete[] way.data;
        }
    }
}

void Cache_tlm_model::b_transport(
    tlm::tlm_generic_payload& trans, 
    sc_core::sc_time& delay
) {
    handle_request(trans, delay);
}


// 处理请求，返回1表示处理成功，返回0表示处理失败
int Cache_tlm_model:: handle_request(
    tlm::tlm_generic_payload& trans,
    sc_core::sc_time& delay
) {
    sc_dt::sc_uint64 addr = trans.get_address();
    unsigned char* data_ptr = trans.get_data_ptr();
    unsigned int data_len = trans.get_data_length();
    tlm::tlm_command cmd = trans.get_command();

    if (data_len > params_.line_size) {
        trans.set_response_status(tlm::TLM_BURST_ERROR_RESPONSE);
        return 0;
    }

    unsigned int offset_bits    = params_.offset_index_bits();
    unsigned int index_bits     = params_.set_index_bits();

    // unsigned int offset_mask    = params_.line_size-1;
    // unsigned int index_mask     = (params_.num_sets-1) << offset_bits;
    unsigned int offset_mask    = gen_offset_mask();
    unsigned int index_mask     = gen_index_mask();

    unsigned int addr_offset         = addr & offset_mask;
    unsigned int addr_index          = (addr & index_mask) >> offset_bits;
    uint64_t     addr_tag            = addr >> (offset_bits + index_bits);

    auto& cache_set = sets_[addr_index];
    bool hit = false;
    CacheLine* hit_line = nullptr;

    for (auto& line : cache_set) {
        if (line.valid && (line.tag == addr_tag)) {
            hit = true;
            hit_line = &line;
            break;
        }
    }

    if (hit) {
        assert(hit_line != nullptr);
        // TODO
        return 1;
    }

    // 缺失处理

    if (cmd == tlm::TLM_READ_COMMAND) {
        read_miss(trans, delay, addr_index, addr_tag, addr_offset);
        return 1;
    } 
    
    else if (cmd == tlm::TLM_WRITE_COMMAND) {
        write_miss(trans, delay, addr_index, addr_tag, addr_offset);
        return 1;
    }

    else {
        //未知命令
        return 0;
    }
}