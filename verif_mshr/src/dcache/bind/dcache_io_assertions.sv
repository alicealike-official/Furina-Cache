module dcache_io_assertions(dcache_interface vif);
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    // cpu受阻时valid和全部载荷保持，直到实际握手。
    a_cpu_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.cpu_valid && !vif.cpu_ready |=> vif.cpu_valid && $stable({vif.cpu_payload_addr, vif.cpu_payload_wrEn, vif.cpu_payload_wData, vif.cpu_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "cpu changed while stalled")
    // cpu有效控制必须已知，有效载荷不能含X/Z。
    a_cpu_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.cpu_valid, vif.cpu_ready}) &&
        (!vif.cpu_valid || !$isunknown({vif.cpu_payload_addr, vif.cpu_payload_wrEn, vif.cpu_payload_wData, vif.cpu_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "cpu contains X/Z")
    // cpuReadResp受阻时valid和全部载荷保持，直到实际握手。
    a_cpuReadResp_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.cpuReadResp_valid && !vif.cpuReadResp_ready |=> vif.cpuReadResp_valid && $stable({vif.cpuReadResp_payload_rData, vif.cpuReadResp_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "cpuReadResp changed while stalled")
    // cpuReadResp有效控制必须已知，有效载荷不能含X/Z。
    a_cpuReadResp_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.cpuReadResp_valid, vif.cpuReadResp_ready}) &&
        (!vif.cpuReadResp_valid || !$isunknown({vif.cpuReadResp_payload_rData, vif.cpuReadResp_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "cpuReadResp contains X/Z")
    // cpuWriteResp受阻时valid和全部载荷保持，直到实际握手。
    a_cpuWriteResp_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.cpuWriteResp_valid && !vif.cpuWriteResp_ready |=> vif.cpuWriteResp_valid && $stable({vif.cpuWriteResp_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "cpuWriteResp changed while stalled")
    // cpuWriteResp有效控制必须已知，有效载荷不能含X/Z。
    a_cpuWriteResp_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.cpuWriteResp_valid, vif.cpuWriteResp_ready}) &&
        (!vif.cpuWriteResp_valid || !$isunknown({vif.cpuWriteResp_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "cpuWriteResp contains X/Z")
    // memReadReq受阻时valid和全部载荷保持，直到实际握手。
    a_memReadReq_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memReadReq_valid && !vif.memReadReq_ready |=> vif.memReadReq_valid && $stable({vif.memReadReq_payload_addr, vif.memReadReq_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "memReadReq changed while stalled")
    // memReadReq有效控制必须已知，有效载荷不能含X/Z。
    a_memReadReq_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.memReadReq_valid, vif.memReadReq_ready}) &&
        (!vif.memReadReq_valid || !$isunknown({vif.memReadReq_payload_addr, vif.memReadReq_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "memReadReq contains X/Z")
    // memWriteReq受阻时valid和全部载荷保持，直到实际握手。
    a_memWriteReq_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memWriteReq_valid && !vif.memWriteReq_ready |=> vif.memWriteReq_valid && $stable({vif.memWriteReq_payload_addr, vif.memWriteReq_payload_wData, vif.memWriteReq_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "memWriteReq changed while stalled")
    // memWriteReq有效控制必须已知，有效载荷不能含X/Z。
    a_memWriteReq_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.memWriteReq_valid, vif.memWriteReq_ready}) &&
        (!vif.memWriteReq_valid || !$isunknown({vif.memWriteReq_payload_addr, vif.memWriteReq_payload_wData, vif.memWriteReq_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "memWriteReq contains X/Z")
    // memReadResp受阻时valid和全部载荷保持，直到实际握手。
    a_memReadResp_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memReadResp_valid && !vif.memReadResp_ready |=> vif.memReadResp_valid && $stable({vif.memReadResp_payload_rData, vif.memReadResp_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "memReadResp changed while stalled")
    // memReadResp有效控制必须已知，有效载荷不能含X/Z。
    a_memReadResp_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.memReadResp_valid, vif.memReadResp_ready}) &&
        (!vif.memReadResp_valid || !$isunknown({vif.memReadResp_payload_rData, vif.memReadResp_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "memReadResp contains X/Z")
    // memWriteResp受阻时valid和全部载荷保持，直到实际握手。
    a_memWriteResp_stable: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        vif.memWriteResp_valid && !vif.memWriteResp_ready |=> vif.memWriteResp_valid && $stable({vif.memWriteResp_payload_id}))
        else `uvm_error("DCACHE_PROTOCOL", "memWriteResp changed while stalled")
    // memWriteResp有效控制必须已知，有效载荷不能含X/Z。
    a_memWriteResp_known: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        !$isunknown({vif.memWriteResp_valid, vif.memWriteResp_ready}) &&
        (!vif.memWriteResp_valid || !$isunknown({vif.memWriteResp_payload_id})))
        else `uvm_error("DCACHE_UNKNOWN", "memWriteResp contains X/Z")
    // CPU整字对齐；内存两方向请求都必须按64字节整行对齐。
    a_alignment: assert property (@(posedge vif.clk) disable iff (!vif.rst_n)
        (!vif.cpu_valid || vif.cpu_payload_addr[1:0] == 0) &&
        (!vif.memReadReq_valid || vif.memReadReq_payload_addr[5:0] == 0) &&
        (!vif.memWriteReq_valid || vif.memWriteReq_payload_addr[5:0] == 0))
        else `uvm_error("DCACHE_ALIGNMENT", "Request address alignment violation")
    // 启动复位采样时，DUT不得呈现旧CPU响应或内存请求；不要求无效载荷为零。
    a_reset_idle: assert property (@(posedge vif.clk)
        !vif.rst_n |-> !vif.cpuReadResp_valid && !vif.cpuWriteResp_valid &&
            !vif.memReadReq_valid && !vif.memWriteReq_valid)
        else `uvm_error("DCACHE_RESET_OUTPUT", "Valid DUT output during reset")
endmodule
