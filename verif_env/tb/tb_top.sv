// tb_top.sv - UVM测试平台的顶层模块
`timescale 1ns/1ps
`include "define.svh"
// import uvm_pkg::*;
// import ID_pkg::*;
// import clk_rst_pkg::*;
// `include "uvm_macros.svh"
module tb_top;

    // ====================================================
    // 时钟和复位信号
    // ====================================================
    bit clk;
    bit rst_n;  

    
    // ====================================================
    // 接口实例化
    // ====================================================
    
    clk_rst_interface clk_rst_vif(clk, rst_n);
    cache_interface cache_vif(clk, rst_n);

    // ====================================================
    // DUT实例化
    // ====================================================
    
    // DUT内部连接信号

    D_cache #(
            .Num_Cache_Set(`NUM_CACHE_SET),
            .Cache_Block_Size(`CACHE_BLOCK_SIZE),
            .Num_Cache_Way(`NUM_CACHE_WAY),
            .DataAddrBus(`DATA_ADDR_BUS),
            .DataWidth(`DATA_WIDTH)
    ) u_D_cache(
                .clk(cache_vif.clk),
                .reset(cache_vif.rst_n),
                .cpu_req_valid(cache_vif.cpu_req_valid),
                .cpu_wr_en(cache_vif.cpu_wr_en),
                .cpu_req_addr(cache_vif.cpu_req_addr),
                .cpu_wdata(cache_vif.cpu_wdata),
                .cache_rdata(cache_vif.cache_rdata), 
                .cpu_req_ready(cache_vif.cpu_req_ready),
                .cpu_resp_valid(cache_vif.cpu_resp_valid),
                .cpu_resp_ready(cache_vif.cpu_resp_ready),
                .mem_req_valid(cache_vif.mem_req_valid),
                .mem_req_ready(cache_vif.mem_req_ready),
                .mem_wr_en(cache_vif.mem_wr_en),
                .mem_addr(cache_vif.mem_addr),
                .mem_wdata(cache_vif.mem_wdata),
                .mem_resp_valid(cache_vif.mem_resp_valid),
                .mem_resp_ready(cache_vif.mem_resp_ready),
                .mem_rdata(cache_vif.mem_rdata)
    );
    
    configurable_delay_mem u_mem(
        .clk(cache_vif.clk),
        .rst_n(cache_vif.rst_n),
        .latency_in(0),
        .mem_req_valid(cache_vif.mem_req_valid),
        .mem_req_ready(cache_vif.mem_req_ready),
        .mem_wr_en(cache_vif.mem_wr_en),
        .mem_addr(cache_vif.mem_addr),
        .mem_wdata(cache_vif.mem_wdata),
        .mem_resp_valid(cache_vif.mem_resp_valid),
        .mem_resp_ready(cache_vif.mem_resp_ready),
        .mem_rdata(cache_vif.mem_rdata)
    );
    
    // ====================================================
    // UVM配置和启动
    // ====================================================
    initial begin
        // 打印banner
        $display("========================================");
        $display("UVM Testbench Top Level");
        $display("Time: %0t", $time);
        $display("========================================");
        
        // // 通过uvm_config_db传递接口句柄
        // uvm_config_db#(virtual ID_interface)::set(null, "*", "ID_vif", ID_vif);
        uvm_config_db#(virtual clk_rst_interface)::set(null,"*","clk_rst_vif",clk_rst_vif);
        uvm_config_db#(virtual cache_interface)::set(null,"*","cache_vif",cache_vif);
        // // 启动UVM测试
        run_test("cache_basic_test");
    end
    
    // ====================================================
    // 波形dump（用于仿真调试）
    // ====================================================
    initial begin
                // 根据命令行参数决定是否dump波形
                    $display("Dumping waveform...");
                    $fsdbDumpfile();
                    $fsdbDumpvars();
                    $fsdbDumpMDA();
    end
    
    // ====================================================
    // 仿真结束控制
    // ====================================================
    initial begin
      #100000; // 仿真运行100us后自动结束
        $display("========================================");
        $display("Simulation timeout reached");
        $display("========================================");
        $finish;
    end
endmodule