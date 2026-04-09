// tb_alu_top.sv
`timescale 1ns/1ps

module tb_alu_top;
    // 时钟和复位
    logic clk;
    logic rst_n;
    
    // DUT接口
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic funct7_5;
    logic imm_10;
    logic [31:0] src_A;
    logic [31:0] src_B;
    logic branch;
    logic branch_estimation;
    logic [31:0] pc;
    logic [31:0] imm;
    
    logic [31:0] alu_result;
    logic alu_zero;
    logic branch_taken;
    logic [31:0] branch_target_actual;
    logic branch_prediction_miss;
    
    // 实例化DUT
    EX dut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7_5(funct7_5),
        .imm_10(imm_10),
        .src_A(src_A),
        .src_B(src_B),
        .branch(branch),
        .branch_estimation(branch_estimation),
        .pc(pc),
        .imm(imm),
        .alu_result(alu_result),
        .alu_zero(alu_zero),
        .branch_taken(branch_taken),
        .branch_target_actual(branch_target_actual),
        .branch_prediction_miss(branch_prediction_miss)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk <= ~clk;
    end
    
    // 复位生成
    initial begin
        rst_n = 0;
        #20 rst_n = 1;
    end
    
    // 测试控制
    initial begin
        // 初始化
        initialize();
        
        // 运行测试
        run_all_tests();
        
        // 结束仿真
        #100;
        $display("========================================");
        $display("All tests completed successfully!");
        $display("========================================");
        $finish;
    end
    
    // 初始化任务
    task initialize();
        opcode = 7'b0;
        funct3 = 3'b0;
        funct7_5 = 1'b0;
        imm_10 = 1'b0;
        src_A = 32'b0;
        src_B = 32'b0;
        branch = 1'b0;
        branch_estimation = 1'b0;
        pc = 32'b0;
        imm = 32'b0;
    endtask
    
    // 运行所有测试
    task run_all_tests();
        $display("========================================");
        $display("Starting RISC-V ALU Verification");
        $display("========================================");
        
        test_rtype_instructions();
        test_itype_instructions();
        test_branch_instructions();
        test_csr_instructions();
        test_special_cases();
        test_random_instructions(100);
        //test_edge_cases();
        test_branch_prediction();
    endtask

    initial begin
                // 根据命令行参数决定是否dump波形
                    $display("Dumping waveform...");
                    $fsdbDumpfile("wave.fsdb");
                    $fsdbDumpvars(0, tb_alu_top);
    end
endmodule