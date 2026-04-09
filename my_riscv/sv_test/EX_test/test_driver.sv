// test_driver.sv
class test_driver;
    int test_id;
    //int pass_count;
    //int fail_count;
    //alu_ref_model ref_model;
    
    //function new();
    //    ref_model = new();
    //    pass_count = 0;
    //    fail_count = 0;
    //endfunction
    
    // task check_result(
    //     string test_name,
    //     logic [31:0] act_result,
    //     logic act_zero,
    //     logic act_taken,
    //     logic [31:0] act_target,
    //     logic act_miss,
    //     logic [31:0] exp_result,
    //     logic exp_zero,
    //     logic exp_taken,
    //     logic [31:0] exp_target,
    //     logic exp_miss
    // );
    //     logic pass;
        
    //     pass = (act_result === exp_result) &&
    //            (act_zero === exp_zero) &&
    //            (act_taken === exp_taken) &&
    //            (act_target === exp_target) &&
    //            (act_miss === exp_miss);
        
    //     if (pass) begin
    //         pass_count++;
    //         $display("[PASS] %s", test_name);
    //     end else begin
    //         fail_count++;
    //         $display("[FAIL] %s", test_name);
    //         $display("  Expected: result=%0d, zero=%b, taken=%b, target=%h, miss=%b", 
    //                  exp_result, exp_zero, exp_taken, exp_target, exp_miss);
    //         $display("  Actual  : result=%0d, zero=%b, taken=%b, target=%h, miss=%b", 
    //                  act_result, act_zero, act_taken, act_target, act_miss);
    //     end
    // endtask
    
    task run_test(
        string test_name,
        logic [6:0] opcode,
        logic [2:0] funct3,
        logic funct7_5,
        logic imm_10,
        logic [31:0] src_A,
        logic [31:0] src_B,
        logic branch,
        logic branch_estimation,
        logic [31:0] pc,
        logic [31:0] imm
    );
        logic [31:0] exp_result, exp_target;
        logic exp_zero, exp_taken, exp_miss;
        
        // 计算预期结果
        // alu_ref_model::calculate_expected(
        //     opcode, funct3, funct7_5, imm_10,
        //     src_A, src_B, pc, imm,
        //     branch, branch_estimation,
        //     exp_result, exp_zero, exp_taken, exp_target, exp_miss
        // );
        
        // 驱动DUT
        @(posedge tb_alu_top.clk);
        tb_alu_top.opcode <= opcode;
        tb_alu_top.funct3 <= funct3;
        tb_alu_top.funct7_5 <= funct7_5;
        tb_alu_top.imm_10 <= imm_10;
        tb_alu_top.src_A <= src_A;
        tb_alu_top.src_B <= src_B;
        tb_alu_top.branch <= branch;
        tb_alu_top.branch_estimation <= branch_estimation;
        tb_alu_top.pc <= pc;
        tb_alu_top.imm <= imm;
        
        // 等待结果
        @(negedge tb_alu_top.clk);
        #1;
        
        // // 检查结果
        // check_result(
        //     test_name,
        //     tb_alu_top.alu_result,
        //     tb_alu_top.alu_zero,
        //     tb_alu_top.branch_taken,
        //     tb_alu_top.branch_target_actual,
        //     tb_alu_top.branch_prediction_miss,
        //     exp_result, exp_zero, exp_taken, exp_target, exp_miss
        // );
    endtask
endclass