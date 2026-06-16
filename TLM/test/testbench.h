#ifndef TESTBENCH_H
#define TESTBENCH_H
#include <systemc>
#include <tlm.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <iostream>
#include <iomanip>
#include <sstream>
// CPU发起端：模拟CPU发送读写请求
class CpuInitiator : public sc_core::sc_module {
public:
    tlm_utils::simple_initiator_socket<CpuInitiator> init_socket;
    SC_CTOR(CpuInitiator) : init_socket("init_socket") {
        SC_THREAD(run_tests);
    }
    void run_tests() {
        wait(10, sc_core::SC_NS);
        std::cout << "=== 测试1: 写入地址 0x1000 ===\n" << write_test(0x1000, 0xDEADBEEF);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试2: 读取地址 0x1000 ===\n" << read_test(0x1000);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试3: 写入地址 0x2000 ===\n" << write_test(0x2000, 0xCAFEBABE);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试4: 读取地址 0x2000 ===\n" << read_test(0x2000);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试5: 读取未写入的地址 0x3000 ===\n" << read_test(0x3000);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试6: 写入地址 0x1004 (同一cache line) ===\n" << write_test(0x1004, 0x12345678);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试7: 读取地址 0x1004 ===\n" << read_test(0x1004);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 测试8: 读取地址 0x1000 (验证同一line) ===\n" << read_test(0x1000);
        wait(20, sc_core::SC_NS);
        std::cout << "=== 所有测试完成 ===\n" << std::endl;
        sc_core::sc_stop();
    }
private:
    std::string write_test(uint64_t addr, uint32_t data) {
        tlm::tlm_generic_payload trans;
        sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
        trans.set_command(tlm::TLM_WRITE_COMMAND);
        trans.set_address(addr);
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&data));
        trans.set_data_length(sizeof(data));
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
        init_socket->b_transport(trans, delay);
        if (trans.get_response_status() == tlm::TLM_OK_RESPONSE) {
            return "写入成功, addr=0x\n" + hex_str(addr) + ", data=0x" + hex_str(data) + ", delay=" + std::to_string(delay.value() / 1000) + "ns";
        } else {
            return "写入失败\n";
        }
    }
    std::string read_test(uint64_t addr) {
        uint32_t data = 0;
        tlm::tlm_generic_payload trans;
        sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
        trans.set_command(tlm::TLM_READ_COMMAND);
        trans.set_address(addr);
        trans.set_data_ptr(reinterpret_cast<unsigned char*>(&data));
        trans.set_data_length(sizeof(data));
        trans.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
        init_socket->b_transport(trans, delay);
        if (trans.get_response_status() == tlm::TLM_OK_RESPONSE) {
            return "读取成功, addr=0x\n" + hex_str(addr) + ", data=0x" + hex_str(data) + ", delay=" + std::to_string(delay.value() / 1000) + "ns";
        } else {
            return "读取失败\n";
        }
    }
    std::string hex_str(uint64_t val) {
        std::stringstream ss;
        ss << std::hex << std::setw(8) << std::setfill('0') << val;
        return ss.str();
    }
};
#endif