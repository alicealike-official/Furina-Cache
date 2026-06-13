// simple_cache.cpp
#include "cache_tlm_ai.h"
#include <cstring>
#include <cmath>

SimpleCache::SimpleCache(sc_core::sc_module_name name, unsigned num_lines, unsigned line_size)
    : 
    sc_core::sc_module(name), 
    cpu_socket("cpu_socket"),
    mem_socket("mem_socket"), 
    num_lines_(num_lines), 
    line_size_(line_size)
{
    // 确保参数是2的幂
    assert((num_lines & (num_lines-1)) == 0);
    assert((line_size & (line_size-1)) == 0);

    offset_bits_ = static_cast<unsigned>(std::log2(line_size_));
    index_bits_  = static_cast<unsigned>(std::log2(num_lines_));
    offset_mask_ = line_size_ - 1;
    index_mask_  = (num_lines_ - 1) << offset_bits_;

    lines_.resize(num_lines_);
    for (auto& line : lines_) {
        line.data = new unsigned char[line_size_];
        std::memset(line.data, 0, line_size_);
    }
}

SimpleCache::~SimpleCache() {
    for (auto& line : lines_) {
        delete[] line.data;
    }
}

void SimpleCache::b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay) {
    handle_request(trans, delay);
}

void SimpleCache::handle_request(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay) {
    sc_dt::uint64 addr = trans.get_address();
    unsigned char* data_ptr = trans.get_data_ptr();
    unsigned int data_len = trans.get_data_length();
    tlm::tlm_command cmd = trans.get_command();

    // 简单起见，要求数据长度不超过一行
    if (data_len > line_size_) {
        trans.set_response_status(tlm::TLM_BURST_ERROR_RESPONSE);
        return;
    }

    unsigned offset = addr & offset_mask_;
    unsigned index  = (addr & index_mask_) >> offset_bits_;
    uint64_t tag    = addr >> (offset_bits_ + index_bits_);

    CacheLine& line = lines_[index];
    bool hit = line.valid && (line.tag == tag);

    // 命中处理
    if (hit) {
        if (cmd == tlm::TLM_READ_COMMAND) {
            std::memcpy(data_ptr, line.data + offset, data_len);
        } else if (cmd == tlm::TLM_WRITE_COMMAND) {
            std::memcpy(line.data + offset, data_ptr, data_len);
            line.dirty = true;
        }
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
        // 缓存命中延迟
        delay += sc_core::sc_time(2, sc_core::SC_NS);
        return;
    }

    // 缺失处理
    if (cmd == tlm::TLM_READ_COMMAND) {
        read_miss(trans, delay, index, tag, offset);
    } else if (cmd == tlm::TLM_WRITE_COMMAND) {
        write_miss(trans, delay, index, tag, offset);
    }
}

void SimpleCache::read_miss(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay,
                            unsigned index, uint64_t tag, unsigned offset) {
    CacheLine& line = lines_[index];

    // 若当前行有效且脏，先写回
    if (line.valid && line.dirty) {
        write_back(index);
    }

    // 从下一级存储读取整个缓存行
    unsigned char* line_buf = new unsigned char[line_size_];
    tlm::tlm_generic_payload mem_trans;
    sc_core::sc_time mem_delay = sc_core::SC_ZERO_TIME;

    // 计算行对齐地址
    sc_dt::uint64 line_addr = (tag << (offset_bits_ + index_bits_)) | (index << offset_bits_);

    mem_trans.set_command(tlm::TLM_READ_COMMAND);
    mem_trans.set_address(line_addr);
    mem_trans.set_data_ptr(line_buf);
    mem_trans.set_data_length(line_size_);
    mem_trans.set_streaming_width(line_size_);
    mem_trans.set_byte_enable_ptr(nullptr);
    mem_trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

    mem_socket->b_transport(mem_trans, mem_delay);
    delay += mem_delay;

    if (mem_trans.get_response_status() != tlm::TLM_OK_RESPONSE) {
        delete[] line_buf;
        trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return;
    }

    // 填充缓存行
    fill_line(index, tag, line_buf);
    delete[] line_buf;

    // 服务原始读请求
    std::memcpy(trans.get_data_ptr(), line.data + offset, trans.get_data_length());
    trans.set_response_status(tlm::TLM_OK_RESPONSE);
    delay += sc_core::sc_time(10, sc_core::SC_NS); // 缺失惩罚
}

void SimpleCache::write_miss(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay,
                             unsigned index, uint64_t tag, unsigned offset) {
    // 写分配策略：先读入行，再修改
    CacheLine& line = lines_[index];

    if (line.valid && line.dirty) {
        write_back(index);
    }

    unsigned char* line_buf = new unsigned char[line_size_];
    tlm::tlm_generic_payload mem_trans;
    sc_core::sc_time mem_delay = sc_core::SC_ZERO_TIME;

    sc_dt::uint64 line_addr = (tag << (offset_bits_ + index_bits_)) | (index << offset_bits_);

    mem_trans.set_command(tlm::TLM_READ_COMMAND);
    mem_trans.set_address(line_addr);
    mem_trans.set_data_ptr(line_buf);
    mem_trans.set_data_length(line_size_);
    mem_trans.set_streaming_width(line_size_);
    mem_trans.set_byte_enable_ptr(nullptr);
    mem_trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

    mem_socket->b_transport(mem_trans, mem_delay);
    delay += mem_delay;

    if (mem_trans.get_response_status() != tlm::TLM_OK_RESPONSE) {
        delete[] line_buf;
        trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
        return;
    }

    fill_line(index, tag, line_buf);
    delete[] line_buf;

    // 写入数据到缓存行
    std::memcpy(line.data + offset, trans.get_data_ptr(), trans.get_data_length());
    line.dirty = true;

    trans.set_response_status(tlm::TLM_OK_RESPONSE);
    delay += sc_core::sc_time(10, sc_core::SC_NS);
}

void SimpleCache::write_back(unsigned index) {
    CacheLine& line = lines_[index];
    if (!line.valid || !line.dirty) return;

    tlm::tlm_generic_payload wb_trans;
    sc_core::sc_time wb_delay = sc_core::SC_ZERO_TIME;

    sc_dt::uint64 addr = (line.tag << (offset_bits_ + index_bits_)) | (index << offset_bits_);

    wb_trans.set_command(tlm::TLM_WRITE_COMMAND);
    wb_trans.set_address(addr);
    wb_trans.set_data_ptr(line.data);
    wb_trans.set_data_length(line_size_);
    wb_trans.set_streaming_width(line_size_);
    wb_trans.set_byte_enable_ptr(nullptr);
    wb_trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

    mem_socket->b_transport(wb_trans, wb_delay);
    // 写回延迟已包含在mem_socket调用中，但未返回给上层；此处忽略，实际模型可累加
    line.dirty = false;
}

void SimpleCache::fill_line(unsigned index, uint64_t tag, const unsigned char* data) {
    CacheLine& line = lines_[index];
    std::memcpy(line.data, data, line_size_);
    line.tag = tag;
    line.valid = true;
    line.dirty = false;
}