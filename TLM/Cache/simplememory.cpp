#include <systemc>
#include <tlm.h>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <vector>
class SimpleMemory : public sc_core::sc_module {
public:
    tlm_utils::simple_target_socket<SimpleMemory> mem_socket;
    SimpleMemory(sc_core::sc_module_name name, unsigned int size)
        : sc_core::sc_module(name), mem_socket("mem_socket"), mem_size(size) {
        mem = new unsigned char[size];
        std::memset(mem, 0, size);
    }
    ~SimpleMemory() { delete[] mem; }
    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay) {
        uint64_t addr = trans.get_address();
        unsigned char* ptr = trans.get_data_ptr();
        unsigned int len = trans.get_data_length();
        if (addr + len > mem_size) {
            trans.set_response_status(tlm::TLM_ADDRESS_ERROR_RESPONSE);
            return;
        }
        if (trans.get_command() == tlm::TLM_READ_COMMAND) {
            std::memcpy(ptr, mem + addr, len);
        } else {
            std::memcpy(mem + addr, ptr, len);
        }
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
        delay += sc_core::sc_time(10, sc_core::SC_NS);
    }
private:
    unsigned char* mem;
    unsigned int mem_size;
};