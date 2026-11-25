// 每个采样沿发布独立的四态IO快照；传给内存driver和C++预测检查链。
class dcache_sample extends uvm_sequence_item;
    logic rst_n;
    logic cpu_valid;
    logic cpu_ready;
    logic [31:0] cpu_payload_addr;
    logic cpu_payload_wrEn;
    logic [31:0] cpu_payload_wData;
    logic [4:0] cpu_payload_id;
    logic cpuReadResp_valid;
    logic cpuReadResp_ready;
    logic [31:0] cpuReadResp_payload_rData;
    logic [4:0] cpuReadResp_payload_id;
    logic cpuWriteResp_valid;
    logic cpuWriteResp_ready;
    logic [4:0] cpuWriteResp_payload_id;
    logic memReadReq_valid;
    logic memReadReq_ready;
    logic [31:0] memReadReq_payload_addr;
    logic [3:0] memReadReq_payload_id;
    logic memWriteReq_valid;
    logic memWriteReq_ready;
    logic [31:0] memWriteReq_payload_addr;
    logic [511:0] memWriteReq_payload_wData;
    logic [3:0] memWriteReq_payload_id;
    logic memReadResp_valid;
    logic memReadResp_ready;
    logic [511:0] memReadResp_payload_rData;
    logic [3:0] memReadResp_payload_id;
    logic memWriteResp_valid;
    logic memWriteResp_ready;
    logic [3:0] memWriteResp_payload_id;
    `uvm_object_utils(dcache_sample)
    function new(string name = "dcache_sample");
        super.new(name);
    endfunction
endclass
