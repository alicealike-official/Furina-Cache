#ifndef UTILS_H
#define UTILS_H

#include <tlm.h>
#include <systemc>
#include <string>
#include <sstream>
#include <iomanip>

// ========== TLM 相关 ==========
inline const char* cmd_to_str(tlm::tlm_command cmd) {
    switch (cmd) {
        case tlm::TLM_READ_COMMAND:    return "READ";
        case tlm::TLM_WRITE_COMMAND:   return "WRITE";
        case tlm::TLM_IGNORE_COMMAND:  return "IGNORE";
        default: return "UNKNOWN";
    }
}


inline const char* resp_to_str(tlm::tlm_response_status status) {
    switch (status) {
        case tlm::TLM_OK_RESPONSE:            return "OK";
        case tlm::TLM_COMMAND_ERROR_RESPONSE:  return "CMD_ERR";
        case tlm::TLM_ADDRESS_ERROR_RESPONSE:  return "ADDR_ERR";
        case tlm::TLM_GENERIC_ERROR_RESPONSE:  return "GEN_ERR";
        case tlm::TLM_BURST_ERROR_RESPONSE:    return "BURST_ERR";
        case tlm::TLM_INCOMPLETE_RESPONSE:     return "INCOMPLETE";
        default: return "UNKNOWN";
    }
}

// // ========== 格式化 ==========
// inline std::string hex_str(uint64_t val, int width = 8) {
//     std::stringstream ss;
//     ss << "0x" << std::hex << std::setw(width) << std::setfill('0') << val;
//     return ss.str();
// }

// inline std::string time_str() {
//     std::stringstream ss;
//     ss << sc_core::sc_time_stamp();
//     return ss.str();
// }
// // ========== 调试打印 ==========
// inline void print_req(const char* tag, tlm::tlm_generic_payload& trans) {
//     std::cout << time_str() << " [" << tag << "] "
//               << cmd_to_str(trans.get_command())
//               << " addr=" << hex_str(trans.get_address())
//               << " len=" << trans.get_data_length()
//               << std::endl;
// }
// inline void print_resp(const char* tag, tlm::tlm_generic_payload& trans) {
//     std::cout << time_str() << " [" << tag << "] "
//               << "resp=" << resp_to_str(trans.get_response_status())
//               << std::endl;
// }

// inline void print_cache_state(const char* tag, 
//     unsigned num_sets, unsigned num_ways,
//     bool* valid, uint64_t* tag_arr, bool* dirty) 
// {
//     std::cout << time_str() << " [" << tag << "] Cache状态:" << std::endl;
//     for (unsigned s = 0; s < num_sets; s++) {
//         for (unsigned w = 0; w < num_ways; w++) {
//             unsigned idx = s * num_ways + w;
//             if (valid[idx]) {
//                 std::cout << "  set[" << s << "] way[" << w << "] "
//                           << "tag=" << hex_str(tag_arr[idx])
//                           << " dirty=" << dirty[idx]
//                           << std::endl;
//             }
//         }
//     }
// }


#endif