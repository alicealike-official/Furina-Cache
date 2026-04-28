package cache_pkg;
    `include "define.svh"
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    //transaction
    `include "cpu_req_transaction.sv"
    `include "cache_rsp_transaction.sv"
    `include "mem_req_transaction.sv"
    `include "mem_rsp_transaction.sv"


    `include "cpu_basic_sequence.sv"

    //功能测试
    `include "cpu_read_hit_sequence.sv"
    `include "cpu_read_miss_sequence.sv"
    `include "cpu_write_hit_sequence.sv"
    `include "cpu_write_miss_sequence.sv"
    `include "cpu_write_read_sequence.sv"

    `include "cpu_tag_match_sequence.sv"


    `include "cache_base_virtual_sequence.sv"

    //driver
    `include "cpu_driver.sv"

    //monitor
    `include "cpu_in_monitor.sv"
    `include "cache_out_monitor.sv"
    `include "mem_req_monitor.sv"
    `include "mem_rsp_monitor.sv"

    //agent
    `include "cpu_agent.sv"
endpackage