// 基础测试
import uvm_pkg::*;
import ID_pkg::*;
import clk_rst_pkg::*;
`include "uvm_macros.svh"
class base_test extends uvm_test;
    ID_env env;
    

    clk_rst_config clk_rst_cfg;
    instr_config instr_cfg;
    `uvm_component_utils(base_test)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ID_env::type_id::create("env", this);
        clk_rst_cfg = clk_rst_config::type_id::create("env", this);
        instr_cfg = instr_config::type_id::create("env", this);

        uvm_config_db#(clk_rst_config)::set(this, "*", "clk_rst_cfg", clk_rst_cfg);
        uvm_config_db#(instr_config)::set(this, "*", "instr_cfg", instr_cfg);
    endfunction
    
    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction
    
    task run_phase(uvm_phase phase);
        base_instr_sequence seq;
        
        phase.raise_objection(this);
        seq = base_instr_sequence::type_id::create("seq");
        repeat(1000) begin
            seq.start(env.ID_agt.sqr);
        end
        if (env.clk_rst_agt.driver != null) begin
            env.clk_rst_agt.driver.stop_clock();
            #20;
        end
        phase.drop_objection(this);
    endtask
endclass

// 所有opcode测试
// class all_opcodes_test extends base_test;
//     `uvm_component_utils(all_opcodes_test)
    
//     task run_phase(uvm_phase phase);
//         specific_opcode_sequence seq;
        
//         phase.raise_objection(this);
        
//         // 遍历所有opcode
//         seq = specific_opcode_sequence::type_id::create("seq");
//         foreach (opcode_list[i]) begin
//             seq.target_opcode = opcode_list[i];
//             seq.start(env.v_sqr);
//         end
        
//         phase.drop_objection(this);
//     endtask
    
//     localparam bit [6:0] opcode_list[11] = '{
//         `OPCODE_LUI, `OPCODE_AUIPC, `OPCODE_JAL, `OPCODE_JALR,
//         `OPCODE_BRANCH, `OPCODE_LOAD, `OPCODE_STORE, `OPCODE_ITYPE,
//         `OPCODE_RTYPE, `OPCODE_FENCE, `OPCODE_ENVIRONMENT
//     };
// endclass

// // CSR指令详细测试
// class csr_detailed_test extends base_test;
//     `uvm_component_utils(csr_detailed_test)
    
//     task run_phase(uvm_phase phase);
//         phase.raise_objection(this);
        
//         // 测试所有CSR funct3值
//         for (int csr_funct3 = 1; csr_funct3 <= 5; csr_funct3++) begin
//             // CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
//             for (int i = 0; i < 10; i++) begin
//                 instr_transaction tx;
//                 tx = instr_transaction::type_id::create("tx");
//                 tx.randomize() with {
//                     instruction[6:0] == `OPCODE_ENVIRONMENT;
//                     instruction[14:12] == csr_funct3;
//                     instruction[19:15] == i; // rs1
//                     instruction[11:7] == i+5; // rd
//                 };
//                 env.v_sqr.cu_sqr.start_item(tx);
//                 env.v_sqr.cu_sqr.finish_item(tx);
//             end
//         end
        
//         phase.drop_objection(this);
//     endtask
// endclass

// // 边界条件测试
// class corner_case_test extends base_test;
//     `uvm_component_utils(corner_case_test)
    
//     task run_phase(uvm_phase phase);
//         corner_case_sequence seq;
        
//         phase.raise_objection(this);
//         seq = corner_case_sequence::type_id::create("seq");
//         seq.start(env.v_sqr);
//         phase.drop_objection(this);
//     endtask
// endclass
