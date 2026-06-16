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
    sets_(params.num_sets, std::vector<CacheLine>(params.num_ways)),
    fifo_queues_(params.num_sets)
{
    cpu_socket.register_b_transport(this, &Cache_tlm_model::b_transport);
    for (auto& set : sets_) {
        for (auto& way : set) {
            way.data = new unsigned char[params_.line_size];
            std::memset(way.data,0,params_.line_size);
        }
    }

    // intial queue is empty
    // for (auto& q : fifo_queues_) {
    //     for (unsigned i = 0; i < params_.num_ways; i++) {
    //         q.push(i);
    //     }
    // }
}


Cache_tlm_model::~Cache_tlm_model() {
    for (auto& set : sets_) {
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
    sc_dt::sc_uint<64> addr = trans.get_address();
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
    unsigned int offset_mask    = params_.gen_offset_mask();
    unsigned int index_mask     = params_.gen_index_mask();

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
        if (cmd == tlm::TLM_READ_COMMAND) {
            std::memcpy(data_ptr, hit_line->data+addr_offset, data_len);
        }
        else if (cmd == tlm::TLM_WRITE_COMMAND) {
            std::memcpy(hit_line->data+addr_offset, data_ptr, data_len);
            hit_line->dirty = 1;
        }

        else {
            // 未知命令
            return 0;
        }

        trans.set_response_status(tlm::TLM_OK_RESPONSE);
        delay += sc_core::sc_time(2,sc_core::SC_NS);
        return 1;
    }

    // 缺失处理
    unsigned victim_way = alloc_way(addr_index);

    if (cmd == tlm::TLM_READ_COMMAND) {
        return read_miss_proc(trans, delay, addr_tag, addr_index, addr_offset, victim_way);
    } 
    
    else if (cmd == tlm::TLM_WRITE_COMMAND) {
        return write_miss_proc(trans, delay, addr_tag, addr_index, addr_offset, victim_way);
    }
    else {
        //未知命令
        return 0;
    }
}

unsigned Cache_tlm_model::alloc_way (unsigned int index) {
    auto& cache_set = sets_[index];
    auto& fifo_q    = fifo_queues_[index];

    // search for empty line
    for (unsigned i=0; i<params_.num_ways; i++) {
        if (!cache_set[i].valid) {
            fifo_q.push(i);
            return i;
        }
    }

    // if no empty lines
    unsigned int victim = fifo_q.front(); // the line head is the oldest way
    fifo_q.pop();
    fifo_q.push(victim); // victim is the yongest way

    if (cache_set[victim].dirty) {
        write_back(index, victim);
    }

    return victim;
}

void Cache_tlm_model::write_back(
    unsigned int set_index,
    unsigned int way_index
) {
    auto& line = sets_[set_index][way_index];
    if (!line.dirty || !line.valid) return;

    tlm::tlm_generic_payload mem_trans;
    //TLM规定发起方的delay为0
    sc_core::sc_time delay=sc_core::SC_ZERO_TIME;

    // 一次性传输一个cache line
    uint64_t mem_addr = (line.tag << (params_.set_index_bits() + params_.offset_index_bits()))
                        | (set_index << params_.offset_index_bits());
    
    mem_trans.set_command(tlm::TLM_WRITE_COMMAND);
    mem_trans.set_address(mem_addr);
    mem_trans.set_data_ptr(line.data);
    mem_trans.set_data_length(params_.line_size);
    // 总线宽度为8
    mem_trans.set_streaming_width(8);
    mem_trans.set_byte_enable_ptr(nullptr);
    mem_trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

    mem_socket->b_transport(mem_trans, delay);
    line.dirty = 0;
}

int Cache_tlm_model::read_miss_proc(
    tlm::tlm_generic_payload& trans,
    sc_core::sc_time& delay,
    unsigned int tag,
    unsigned int index,
    unsigned int offset,
    unsigned int way
) {
    auto& line = sets_[index][way];
    // 向内存发起请求
    tlm::tlm_generic_payload mem_trans;
    sc_core::sc_time mem_delay = sc_core::SC_ZERO_TIME;
    unsigned char* line_buf = new unsigned char[params_.line_size];

    uint64_t mem_addr = (tag << (params_.set_index_bits() + params_.offset_index_bits()))
                        | (index << params_.offset_index_bits());
    
    mem_trans.set_command(tlm::TLM_READ_COMMAND);
    mem_trans.set_address(mem_addr);
    mem_trans.set_data_ptr(line_buf);
    mem_trans.set_data_length(params_.line_size);
    // 总线宽度为8
    mem_trans.set_streaming_width(8);
    mem_socket->b_transport(mem_trans,mem_delay);
    delay += mem_delay;

    if (mem_trans.get_response_status() != tlm::TLM_OK_RESPONSE) {
        delete[] line_buf;
        trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return 0;
    }

    std::memcpy(line.data, line_buf, params_.line_size);
    line.tag = tag;
    line.valid = 1;
    line.dirty = 0;
    delete[] line_buf;

    std::memcpy(trans.get_data_ptr(), line.data+offset, trans.get_data_length());
    trans.set_response_status(tlm::TLM_OK_RESPONSE);
    delay += sc_core::sc_time(params_.miss_latency, sc_core::SC_NS);
    return 1;
}

int Cache_tlm_model::write_miss_proc(
    tlm::tlm_generic_payload& trans,
    sc_core::sc_time& delay,
    unsigned int tag,
    unsigned int index,
    unsigned int offset,
    unsigned int way
) {
    auto& line = sets_[index][way];
    // 向内存发起请求
    tlm::tlm_generic_payload mem_trans;
    sc_core::sc_time mem_delay = sc_core::SC_ZERO_TIME;
    unsigned char* line_buf = new unsigned char[params_.line_size];

    uint64_t mem_addr = (tag << (params_.set_index_bits() + params_.offset_index_bits()))
                        | (index << params_.offset_index_bits());
    
    mem_trans.set_command(tlm::TLM_READ_COMMAND);
    mem_trans.set_address(mem_addr);
    mem_trans.set_data_ptr(line_buf);
    mem_trans.set_data_length(params_.line_size);
    // 总线宽度为8
    mem_trans.set_streaming_width(8);
    mem_socket->b_transport(mem_trans,mem_delay);
    delay += mem_delay;

    if (mem_trans.get_response_status() != tlm::TLM_OK_RESPONSE) {
        delete[] line_buf;
        trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return 0;
    }

    std::memcpy(line.data, line_buf, params_.line_size);
    line.tag = tag;
    line.valid = 1;
    
    delete[] line_buf;

    std::memcpy(line.data+offset, trans.get_data_ptr(), trans.get_data_length());
    line.dirty = 1;
    trans.set_response_status(tlm::TLM_OK_RESPONSE);
    delay += sc_core::sc_time(params_.miss_latency, sc_core::SC_NS);
    return 1;
}