package mshr_pkg;
    timeunit 1ns;
    timeprecision 1ps;
    import uvm_pkg::*;
    import mshr_params_pkg::*;
    import clk_rst_pkg::*;
    `include "uvm_macros.svh"
    `include "vutils_macros.svh"
    // 导入C++ MSHR/SparseMemory的DPI声明，函数体由dpi/mshr_dpi.cpp链接提供。
    `include "pkg/mshr_dpi.svh"
    `include "config/mshr_config.sv"
    `include "sequence/transaction/mshr_transaction.sv"
    `include "sequence/transaction/mshr_sample.sv"
    `include "sequence/transaction/mshr_compare_item.sv"
    `include "component/agent/mshr_sequencer.sv"
    `include "component/driver/mshr_driver.sv"
    `include "component/monitor/mshr_monitor.sv"
    `include "component/agent/mshr_agent.sv"
    `include "model/mshr_memory_store.sv"
    `include "model/mshr_predictor.sv"
    `include "component/driver/mshr_memory_driver.sv"
    `include "component/driver/mshr_sink_driver.sv"
    `include "component/agent/mshr_memory_agent.sv"
    `include "component/scoreboard/mshr_scoreboard.sv"
    `include "component/mshr_environment.sv"
    `include "sequence/mshr_base_sequence.sv"
    `include "sequence/mshr_smoke_sequence.sv"
endpackage
