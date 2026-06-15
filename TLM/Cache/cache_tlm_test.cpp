#include "cache_tlm.h"
#include "simplememory.cpp"
#include <iostream>
int sc_main(int argc, char* argv[]) {
    // 参数: 4组, 4路, 64字节行
    CacheParams params(4, 4, 64);
    Cache_tlm_model cache("cache", params);
    SimpleMemory ram("ram", 4096);
    // 关键：连接 cache 和内存
    cache.mem_socket.bind(ram.mem_socket);
    // 构造一个读事务
    tlm::tlm_generic_payload trans;
    sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
    unsigned char data[4] = {0};
    // 测试1: 读缺失 — 从空cache读地址0x00
    trans.set_command(tlm::TLM_READ_COMMAND);
    trans.set_address(0x00);
    trans.set_data_ptr(data);
    trans.set_data_length(4);
    trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
    cache.b_transport(trans, delay);
    std::cout << "Read miss: resp=" << trans.get_response_status()
              << " delay=" << delay << std::endl;
    // 测试2: 读命中 — 再次读地址0x00
    delay = sc_core::SC_ZERO_TIME;
    cache.b_transport(trans, delay);
    std::cout << "Read hit: resp=" << trans.get_response_status()
              << " delay=" << delay << std::endl;
    // 测试3: 写缺失 — 写地址0x40（不同组）
    unsigned char wdata[4] = {0xDE, 0xAD, 0xBE, 0xEF};
    trans.set_command(tlm::TLM_WRITE_COMMAND);
    trans.set_address(0x40);
    trans.set_data_ptr(wdata);
    trans.set_data_length(4);
    delay = sc_core::SC_ZERO_TIME;
    cache.b_transport(trans, delay);
    std::cout << "Write miss: resp=" << trans.get_response_status()
              << " delay=" << delay << std::endl;
    // 测试4: 写命中 — 再次写地址0x40
    delay = sc_core::SC_ZERO_TIME;
    cache.b_transport(trans, delay);
    std::cout << "Write hit: resp=" << trans.get_response_status()
              << " delay=" << delay << std::endl;
    // 测试5: 读回验证 — 读地址0x40
    trans.set_command(tlm::TLM_READ_COMMAND);
    trans.set_address(0x40);
    trans.set_data_ptr(data);
    trans.set_data_length(4);
    delay = sc_core::SC_ZERO_TIME;
    cache.b_transport(trans, delay);
    std::cout << "Read back: resp=" << trans.get_response_status()
              << " data=" << std::hex
              << (int)data[0] << (int)data[1]
              << (int)data[2] << (int)data[3] << std::endl;
    // 测试6: FIFO替换 — 同组写满4路后再写第5个地址触发替换
    // 组0: 地址 0x00, 0x100, 0x200, 0x300 → 占满4路
    // 写 0x400 → 触发FIFO替换 way0
    for (int i = 0; i < 4; i++) {
        trans.set_command(tlm::TLM_WRITE_COMMAND);
        trans.set_address(i * 0x100);  // 同组不同tag
        trans.set_data_ptr(wdata);
        trans.set_data_length(4);
        delay = sc_core::SC_ZERO_TIME;
        cache.b_transport(trans, delay);
    }
    // 第5个地址，触发替换
    trans.set_command(tlm::TLM_WRITE_COMMAND);
    trans.set_address(0x400);
    trans.set_data_ptr(wdata);
    trans.set_data_length(4);
    delay = sc_core::SC_ZERO_TIME;
    cache.b_transport(trans, delay);
    std::cout << "FIFO replace: resp=" << trans.get_response_status()
              << " delay=" << delay << std::endl;
    return 0;
}