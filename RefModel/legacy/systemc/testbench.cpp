#include "testbench.h"
#include "cache_tlm.h"
#include "sparse_memory.h"
#include <iostream>
int sc_main(int argc, char* argv[]) {
    // 创建模块
    CpuInitiator cpu("cpu");
    CacheParams cache_params(4, 4, 16);  // 4组, 4路, 每行16字节
    Cache_tlm_model cache("cache", cache_params);
    Sparse_Memory memory("memory", 4096, 10);  // 4KB页面, 10ns延迟

    // 连接模块: CPU -> Cache -> Memory
    cpu.init_socket.bind(cache.cpu_socket);
    cache.mem_socket.bind(memory.mem_receive_socket);
    std::cout << "=== 开始测试 ===" << std::endl;
    std::cout << "Cache配置: 4组, 4路, 每行16字节" << std::endl;
    std::cout << "内存配置: 4KB页面, 10ns延迟" << std::endl;
    std::cout << "================" << std::endl;
    sc_core::sc_start();
    std::cout << "=== 测试结束 ===" << std::endl;
    return 0;
}

