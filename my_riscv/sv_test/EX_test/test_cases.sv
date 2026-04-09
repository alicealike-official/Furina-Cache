// test_cases.sv
import riscv_pkg::*;

task test_rtype_instructions();
    test_driver driver = new();
    $display("\n--- Testing R-type Instructions ---");
    
    // ADD测试
    driver.run_test("ADD: 5 + 3 = 8",
        OPCODE_RTYPE, RTYPE_ADDSUB, 1'b0, 1'b0,
        32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    driver.run_test("ADD: -5 + 3 = -2",
        OPCODE_RTYPE, RTYPE_ADDSUB, 1'b0, 1'b0,
        -32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SUB测试
    driver.run_test("SUB: 5 - 3 = 2",
        OPCODE_RTYPE, RTYPE_ADDSUB, 1'b1, 1'b0,
        32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    driver.run_test("SUB: 3 - 5 = -2",
        OPCODE_RTYPE, RTYPE_ADDSUB, 1'b1, 1'b0,
        32'd3, 32'd5, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // AND测试
    driver.run_test("AND: 0xF0F0 & 0xFF00 = 0xF000",
        OPCODE_RTYPE, RTYPE_AND, 1'b0, 1'b0,
        32'h0000F0F0, 32'h0000FF00, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // OR测试
    driver.run_test("OR: 0xF0F0 | 0x0F0F = 0xFFFF",
        OPCODE_RTYPE, RTYPE_OR, 1'b0, 1'b0,
        32'hF0F0F0F0, 32'h0F0F0F0F, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // XOR测试
    driver.run_test("XOR: 0xFFFF0000 ^ 0xFFFF0000 = 0",
        OPCODE_RTYPE, RTYPE_XOR, 1'b0, 1'b0,
        32'hFFFF0000, 32'hFFFF0000, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SLT测试
    driver.run_test("SLT: -5 < 3 = 1",
        OPCODE_RTYPE, RTYPE_SLT, 1'b0, 1'b0,
        -32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    driver.run_test("SLT: 5 < -3 = 0",
        OPCODE_RTYPE, RTYPE_SLT, 1'b0, 1'b0,
        32'd5, -32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SLTU测试
    driver.run_test("SLTU: 0x80000000 < 1 = 0 (unsigned)",
        OPCODE_RTYPE, RTYPE_SLTU, 1'b0, 1'b0,
        32'h80000000, 32'd1, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SLL测试
    driver.run_test("SLL: 5 << 3 = 40",
        OPCODE_RTYPE, RTYPE_SLL, 1'b0, 1'b0,
        32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SRL测试
    driver.run_test("SRL: 0xF0000000 >> 4 = 0x0F000000",
        OPCODE_RTYPE, RTYPE_SR, 1'b0, 1'b0,
        32'hF0000000, 32'd4, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SRA测试
    driver.run_test("SRA: -16 >> 2 = -4",
        OPCODE_RTYPE, RTYPE_SR, 1'b1, 1'b0,
        -32'd16, 32'd2, 1'b0, 1'b0, 32'b0, 32'b0);
    
//    $display("R-type tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask

task test_itype_instructions();
    test_driver driver = new();
    $display("\n--- Testing I-type Instructions ---");
    
    // ADDI测试
    driver.run_test("ADDI: 5 + 3 = 8",
        OPCODE_ITYPE, ITYPE_ADDI, 1'b0, 1'b0,
        32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // ANDI测试
    driver.run_test("ANDI: 0xF0F0 & 0xFF00 = 0xF000",
        OPCODE_ITYPE, ITYPE_ANDI, 1'b0, 1'b0,
        32'h0000F0F0, 32'h0000FF00, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // ORI测试
    driver.run_test("ORI: 0xF0F0 | 0x0F0F = 0xFFFF",
        OPCODE_ITYPE, ITYPE_ORI, 1'b0, 1'b0,
        32'hF0F0F0F0, 32'h0F0F0F0F, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // XORI测试
    driver.run_test("XORI: 0xFFFF0000 ^ 0xFFFF0000 = 0",
        OPCODE_ITYPE, ITYPE_XORI, 1'b0, 1'b0,
        32'hFFFF0000, 32'hFFFF0000, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SLLI测试
    driver.run_test("SLLI: 5 << 3 = 40",
        OPCODE_ITYPE, ITYPE_SLLI, 1'b0, 1'b0,
        32'd5, 32'd3, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SRLI测试
    driver.run_test("SRLI: 0xF0000000 >> 4 = 0x0F000000",
        OPCODE_ITYPE, ITYPE_SRXI, 1'b0, 1'b0,
        32'hF0000000, 32'd4, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // SRAI测试
    driver.run_test("SRAI: -16 >> 2 = -4",
        OPCODE_ITYPE, ITYPE_SRXI, 1'b0, 1'b1,
        -32'd16, 32'd2, 1'b0, 1'b0, 32'b0, 32'b0);
    
//    $display("I-type tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask

task test_branch_instructions();
    test_driver driver = new();
    logic [31:0] test_pc = 32'h00001000;
    logic [31:0] test_imm = 32'h00000020;
    
    $display("\n--- Testing Branch Instructions ---");
    
    // BEQ测试
    driver.run_test("BEQ: 5==5, should branch",
        OPCODE_BRANCH, BRANCH_BEQ, 1'b0, 1'b0,
        32'd5, 32'd5, 1'b1, 1'b0, test_pc, test_imm);
    
    driver.run_test("BEQ: 5!=6, should not branch",
        OPCODE_BRANCH, BRANCH_BEQ, 1'b0, 1'b0,
        32'd5, 32'd6, 1'b1, 1'b1, test_pc, test_imm);
    
    // BNE测试
    driver.run_test("BNE: 5!=6, should branch",
        OPCODE_BRANCH, BRANCH_BNE, 1'b0, 1'b0,
        32'd5, 32'd6, 1'b1, 1'b1, test_pc, test_imm);
    
    driver.run_test("BNE: 5==5, should not branch",
        OPCODE_BRANCH, BRANCH_BNE, 1'b0, 1'b0,
        32'd5, 32'd5, 1'b1, 1'b0, test_pc, test_imm);
    
    // BLT测试
    driver.run_test("BLT: -5 < 3, should branch",
        OPCODE_BRANCH, BRANCH_BLT, 1'b0, 1'b0,
        -32'd5, 32'd3, 1'b1, 1'b0, test_pc, test_imm);
    
    driver.run_test("BLT: 5 < -3, should not branch",
        OPCODE_BRANCH, BRANCH_BLT, 1'b0, 1'b0,
        32'd5, -32'd3, 1'b1, 1'b1, test_pc, test_imm);
    
    // BGE测试
    driver.run_test("BGE: 5 >= 3, should branch",
        OPCODE_BRANCH, BRANCH_BGE, 1'b0, 1'b0,
        32'd5, 32'd3, 1'b1, 1'b0, test_pc, test_imm);
    
    driver.run_test("BGE: -5 >= 3, should not branch",
        OPCODE_BRANCH, BRANCH_BGE, 1'b0, 1'b0,
        -32'd5, 32'd3, 1'b1, 1'b1, test_pc, test_imm);
    
    // BLTU测试
    driver.run_test("BLTU: 1 < 2 (unsigned), should branch",
        OPCODE_BRANCH, BRANCH_BLTU, 1'b0, 1'b0,
        32'd1, 32'd2, 1'b1, 1'b0, test_pc, test_imm);
    
    // BGEU测试
    driver.run_test("BGEU: 0x80000000 >= 1 (unsigned), should branch",
        OPCODE_BRANCH, BRANCH_BGEU, 1'b0, 1'b0,
        32'h80000000, 32'd1, 1'b1, 1'b0, test_pc, test_imm);
    
//    $display("Branch tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask

task test_csr_instructions();
    test_driver driver = new();
    $display("\n--- Testing CSR Instructions ---");
    
    // CSRRW测试
    driver.run_test("CSRRW: pass src_A directly",
        OPCODE_ENVIRONMENT, CSR_CSRRW, 1'b0, 1'b0,
        32'hDEADBEEF, 32'h12345678, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // CSRRS测试
    driver.run_test("CSRRS: src_A | src_B",
        OPCODE_ENVIRONMENT, CSR_CSRRS, 1'b0, 1'b0,
        32'hF0F0F0F0, 32'h0F0F0F0F, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // CSRRC测试
    driver.run_test("CSRRC: src_B & ~src_A",
        OPCODE_ENVIRONMENT, CSR_CSRRC, 1'b0, 1'b0,
        32'hFF00FF00, 32'hF0F0F0F0, 1'b0, 1'b0, 32'b0, 32'b0);
    
//    $display("CSR tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask

task test_special_cases();
    test_driver driver = new();
    $display("\n--- Testing Special Cases ---");
    
    // 加法溢出
    driver.run_test("ADD Overflow: 0x7FFFFFFF + 1 = 0x80000000",
        OPCODE_RTYPE, RTYPE_ADDSUB, 1'b0, 1'b0,
        32'h7FFFFFFF, 32'd1, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // 减法溢出
    driver.run_test("SUB Overflow: 0x80000000 - 1 = 0x7FFFFFFF",
        OPCODE_RTYPE, RTYPE_ADDSUB, 1'b1, 1'b0,
        32'h80000000, 32'd1, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // 移位量大于31
    driver.run_test("SLL: shift amount > 31",
        OPCODE_RTYPE, RTYPE_SLL, 1'b0, 1'b0,
        32'd5, 32'd33, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // 零值比较
    driver.run_test("SLT: 0 < 0 = 0",
        OPCODE_RTYPE, RTYPE_SLT, 1'b0, 1'b0,
        32'd0, 32'd0, 1'b0, 1'b0, 32'b0, 32'b0);
    
    // 全1操作
    driver.run_test("AND: 0xFFFFFFFF & 0xFFFFFFFF = 0xFFFFFFFF",
        OPCODE_RTYPE, RTYPE_AND, 1'b0, 1'b0,
        32'hFFFFFFFF, 32'hFFFFFFFF, 1'b0, 1'b0, 32'b0, 32'b0);
    
 //   $display("Special case tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask

task test_random_instructions(int num_tests);
    test_driver driver = new();
    $display("\n--- Testing %0d Random Instructions ---", num_tests);
    
    repeat (num_tests) begin
        logic [6:0] rand_opcode;
        logic [2:0] rand_funct3;
        logic rand_funct7_5;
        logic rand_imm_10;
        logic [31:0] rand_src_A;
        logic [31:0] rand_src_B;
        logic rand_branch;
        logic rand_estimation;
        logic [31:0] rand_pc;
        logic [31:0] rand_imm;
        
        // 生成随机指令
        rand_opcode = $urandom_range(0, 127);
        rand_funct3 = $urandom_range(0, 7);
        rand_funct7_5 = $urandom;
        rand_imm_10 = $urandom;
        rand_src_A = $urandom;
        rand_src_B = $urandom;
        rand_branch = $urandom_range(0, 1);
        rand_estimation = $urandom_range(0, 1);
        rand_pc = $urandom;
        rand_imm = $urandom;
        
        driver.run_test($sformatf("Random test %0d", driver.test_id++),
            rand_opcode, rand_funct3, rand_funct7_5, rand_imm_10,
            rand_src_A, rand_src_B, rand_branch, rand_estimation,
            rand_pc, rand_imm);
    end
    
//    $display("Random tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask

// task test_edge_cases();
//     test_driver driver = new();
//     $display("\n--- Testing Edge Cases ---");
    
//     // 边界值列表
//     logic [31:0] edge_values[] = {
//         32'h00000000,  // 0
//         32'h00000001,  // 1
//         32'h7FFFFFFF,  // 最大正数
//         32'h80000000,  // 最小负数
//         32'hFFFFFFFF,  // -1
//         32'hAAAAAAAA,  // 交替位
//         32'h55555555,  // 交替位
//         32'hF0F0F0F0,  // 模式
//         32'h0F0F0F0F   // 模式
//     };
    
//     foreach (edge_values[i]) begin
//         foreach (edge_values[j]) begin
//             // ADD测试
//             driver.run_test($sformatf("ADD edge: %h + %h", edge_values[i], edge_values[j]),
//                 OPCODE_RTYPE, RTYPE_ADDSUB, 1'b0, 1'b0,
//                 edge_values[i], edge_values[j], 1'b0, 1'b0, 32'b0, 32'b0);
            
//             // SUB测试
//             driver.run_test($sformatf("SUB edge: %h - %h", edge_values[i], edge_values[j]),
//                 OPCODE_RTYPE, RTYPE_ADDSUB, 1'b1, 1'b0,
//                 edge_values[i], edge_values[j], 1'b0, 1'b0, 32'b0, 32'b0);
            
//             // AND测试
//             driver.run_test($sformatf("AND edge: %h & %h", edge_values[i], edge_values[j]),
//                 OPCODE_RTYPE, RTYPE_AND, 1'b0, 1'b0,
//                 edge_values[i], edge_values[j], 1'b0, 1'b0, 32'b0, 32'b0);
//         end
//     end
    
//     $display("Edge case tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
// endtask

task test_branch_prediction();
    test_driver driver = new();
    logic [31:0] test_pc = 32'h00001000;
    logic [31:0] test_imm = 32'h00000020;
    
    $display("\n--- Testing Branch Prediction ---");
    
    // 预测命中（正确预测跳转）
    driver.run_test("Prediction hit: predict taken, actually taken",
        OPCODE_BRANCH, BRANCH_BEQ, 1'b0, 1'b0,
        32'd5, 32'd5, 1'b1, 1'b1, test_pc, test_imm);
    
    // 预测命中（正确预测不跳）
    driver.run_test("Prediction hit: predict not taken, actually not taken",
        OPCODE_BRANCH, BRANCH_BEQ, 1'b0, 1'b0,
        32'd5, 32'd6, 1'b1, 1'b0, test_pc, test_imm);
    
    // 预测失误（预测跳转但实际上不跳）
    driver.run_test("Prediction miss: predict taken, actually not taken",
        OPCODE_BRANCH, BRANCH_BEQ, 1'b0, 1'b0,
        32'd5, 32'd6, 1'b1, 1'b1, test_pc, test_imm);
    
    // 预测失误（预测不跳但实际上跳转）
    driver.run_test("Prediction miss: predict not taken, actually taken",
        OPCODE_BRANCH, BRANCH_BEQ, 1'b0, 1'b0,
        32'd5, 32'd5, 1'b1, 1'b0, test_pc, test_imm);
    
//    $display("Branch prediction tests: PASS=%0d, FAIL=%0d", driver.pass_count, driver.fail_count);
endtask