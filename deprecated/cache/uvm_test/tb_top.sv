// tb_top.sv - UVM测试平台的顶层模块
`timescale 1ns/1ps
import uvm_pkg::*;
import ID_pkg::*;
import clk_rst_pkg::*;
`include "uvm_macros.svh"
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

    // ID接口
    ID_interface ID_vif (
        .clock(clk_rst_vif.clk)
    );
    

    // ====================================================
    // DUT实例化
    // ====================================================
    
    // DUT内部连接信号


        wire [6:0] opcode;
        wire [2:0] funct3;
        wire [6:0] funct7;
        wire [4:0] rs1;
        wire [4:0] rs2;
        wire [4:0] rd;
        wire [31:0] imm;

        wire jump;
        wire branch;
        wire [1:0] alu_src_A_select;
        wire [2:0] alu_src_B_select;
        wire csr_write_enable;
        wire register_file_write;
        wire [2:0] register_file_write_data_select;        
        wire memory_read;
        wire memory_write;

    
    ID_top u_dut(
        .instruction(ID_vif.instruction),
        .opcode(ID_vif.opcode),
        .funct3(ID_vif.funct3),
        .funct7(ID_vif.funct7),
        .rs1(ID_vif.rs1),
        .rs2(ID_vif.rs2),
        .rd(ID_vif.rd),
        .imm(ID_vif.imm),
        .jump(ID_vif.jump),
        .branch(ID_vif.branch),
        .alu_src_A_select(ID_vif.alu_src_A_select),
        .alu_src_B_select(ID_vif.alu_src_B_select),
        .csr_write_enable(ID_vif.csr_write_enable),
        .register_file_write(ID_vif.register_file_write),
        .register_file_write_data_select(ID_vif.register_file_write_data_select),
        .memory_read(ID_vif.memory_read),
        .memory_write(ID_vif.memory_write)
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
        
        // 通过uvm_config_db传递接口句柄
        uvm_config_db#(virtual ID_interface)::set(null, "*", "ID_vif", ID_vif);
        uvm_config_db#(virtual clk_rst_interface)::set(null,"*","clk_rst_vif",clk_rst_vif);
        // 启动UVM测试
        run_test("base_test");
    end
    
    // ====================================================
    // 波形dump（用于仿真调试）
    // ====================================================
    initial begin
                // 根据命令行参数决定是否dump波形
                    $display("Dumping waveform...");
                    $fsdbDumpfile("wave.fsdb");
                    $fsdbDumpvars(0, tb_top);
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