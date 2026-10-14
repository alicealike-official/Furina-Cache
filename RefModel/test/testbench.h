#ifndef TESTBENCH_H
#define TESTBENCH_H
#include <systemc>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <random>
#include <vector>
#include <map>

struct TestTransaction {
    uint64_t addr;
    bool is_write;
    uint32_t data;  
};
// CPU发起端：模拟CPU发送读写请求
class CpuInitiator : public sc_core::sc_module {
public:
    unsigned pass_count = 0;
    unsigned fail_count = 0;
    tlm_utils::simple_initiator_socket<CpuInitiator> init_socket;
    SC_CTOR(CpuInitiator) : init_socket("init_socket") {
        SC_THREAD(run_tests);
    }
    void run_tests() {
        std::mt19937_64 rng(42);
        const int NUM_TRANSACTIONS = 9000;
        const uint64_t ADDR_BASE = 0x1000;
        const uint64_t ADDR_RANGE = 0x4000;
        //生成随机事务
        std::vector<TestTransaction> transactions;
        for (int i=0; i<NUM_TRANSACTIONS; i++) {
            TestTransaction t;
            uint32_t raw = rng();
            t.addr = ADDR_BASE + (raw % (ADDR_RANGE /4)) * 4;
            t.is_write = (raw>>31) & 1;
            t.data = raw & 0x7FFFFFFF;
            transactions.push_back(t);
        }

        // 按顺序计算期望值
        // addr_state记录了所有的操作，包括第一次读取被赋值给0
        std::map<uint64_t, uint32_t> addr_state;
        std::vector<uint32_t> expected_values;

        for (auto& t : transactions) {
            if (t.is_write) {
                addr_state[t.addr] = t.data;
            }

            else {
                if (addr_state.find(t.addr) == addr_state.end()) {
                    addr_state[t.addr] == 0;
                }
                expected_values.push_back(addr_state[t.addr]);
            }
        }

        wait(10, sc_core::SC_NS);

        // expected不仅要验证读取数据的正确性，还要验证读取次数和顺序的正确性
        int read_idx = 0;

        for(auto& t : transactions) {
            if(t.is_write){
                write_to(t.addr, t.data);
                wait(5, sc_core::SC_NS);
            }

            else {
                uint32_t actual = read_from(t.addr);
                uint32_t expected = expected_values[read_idx++];
                if(actual == expected) {
                    std::cout << "[PASS] read data=0x" << std::hex << actual << std::endl;
                    pass_count++;
                }

                else {
                    std::cout << "[FAIL] expected=0x" << std::hex << expected
                            << " actual=0x" << actual << std::endl;
                    fail_count++;
                }
                wait(5,sc_core::SC_NS);
            }
        }
        // std::cout << "=== 测试1: 写入地址 0x1000 ===\n" << write_test(0x1000, 0xDEADBEEF);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试2: 读取地址 0x1000 ===\n" << read_test(0x1000);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试3: 写入地址 0x2000 ===\n" << write_test(0x2000, 0xCAFEBABE);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试4: 读取地址 0x2000 ===\n" << read_test(0x2000);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试5: 读取未写入的地址 0x3000 ===\n" << read_test(0x3000);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试6: 写入地址 0x1004 (同一cache line) ===\n" << write_test(0x1004, 0x12345678);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试7: 读取地址 0x1004 ===\n" << read_test(0x1004);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 测试8: 读取地址 0x1000 (验证同一line) ===\n" << read_test(0x1000);
        // wait(20, sc_core::SC_NS);
        // std::cout << "=== 所有测试完成 ===\n" << std::endl;
        // sc_core::sc_stop();
        // 打印结果
        std::cout << std::dec;
        std::cout << "============================" << std::endl;
        std::cout << "测试结果: " << pass_count << " 通过, " << fail_count << " 失败" << std::endl;
        std::cout << "============================" << std::endl;
    }
private:

    // void check_write_read(uint64_t addr, uint32_t expected) {
    //     write_to(addr, expected);
    //     uint32_t actual = read_from(addr);
    //     if (actual == expected) {
    //         std::cout << "[PASS] addr=0x" << std::hex << addr
    //                   << " write=0x" << expected << " read=0x" << actual << std::endl;
    //         pass_count++;
    //     } 
        
    //     else {
    //         std::cout << "[FAIL] addr=0x" << std::hex << addr
    //                   << " expected=0x" << expected << " got=0x" << actual << std::endl;
    //         fail_count++;
    //     }
    // }


    uint32_t read_from(uint64_t addr) {
        uint32_t data;
        tlm::tlm_generic_payload trans;
        sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
        trans.set_command(tlm::TLM_READ_COMMAND);
        trans.set_address(addr);
        //将指向uint32_t强制转化为unsigned char*
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&data));
        trans.set_data_length(sizeof(data));
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
        init_socket -> b_transport(trans, delay);
        return data;
    }

    void write_to(uint64_t addr, uint32_t data) {
        tlm::tlm_generic_payload trans;
        sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
        trans.set_command(tlm::TLM_WRITE_COMMAND);
        trans.set_address(addr);
        //将指向uint32_t强制转化为unsigned char*
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&data));
        trans.set_data_length(sizeof(data));
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
        init_socket -> b_transport(trans, delay);
        return;
    }
};
#endif