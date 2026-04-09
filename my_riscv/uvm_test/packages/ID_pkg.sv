package ID_pkg;

        import uvm_pkg::*;
        `include "uvm_macros.svh"

        typedef enum bit [6:0] {
                OPCODE_LOAD     = 7'b0000011,
                OPCODE_STORE    = 7'b0100011,
                OPCODE_BRANCH   = 7'b1100011,
                OPCODE_JALR     = 7'b1100111,
                OPCODE_JAL      = 7'b1101111,
                OPCODE_OP_IMM   = 7'b0010011,
                OPCODE_OP       = 7'b0110011,
                OPCODE_AUIPC    = 7'b0010111,
                OPCODE_LUI      = 7'b0110111,
                OPCODE_SYSTEM   = 7'b1110011
        } rv32i_opcode_e;


        // 指令类型
        typedef enum {
                INSTR_TYPE_R,
                INSTR_TYPE_I,
                INSTR_TYPE_S,
                INSTR_TYPE_B,
                INSTR_TYPE_U,
                INSTR_TYPE_J
        } instr_type_e;

        // LOAD指令的funct3
        parameter [2:0] F3_LOAD_LB  = 3'b000;
        parameter [2:0] F3_LOAD_LH  = 3'b001;
        parameter [2:0] F3_LOAD_LW  = 3'b010;
        parameter [2:0] F3_LOAD_LBU = 3'b100;
        parameter [2:0] F3_LOAD_LHU = 3'b101;

        // STORE指令的funct3
        parameter [2:0] F3_STORE_SB = 3'b000;
        parameter [2:0] F3_STORE_SH = 3'b001;
        parameter [2:0] F3_STORE_SW = 3'b010;

        // BRANCH指令的funct3
        parameter [2:0] F3_BRANCH_BEQ  = 3'b000;
        parameter [2:0] F3_BRANCH_BNE  = 3'b001;
        parameter [2:0] F3_BRANCH_BLT  = 3'b100;
        parameter [2:0] F3_BRANCH_BGE  = 3'b101;
        parameter [2:0] F3_BRANCH_BLTU = 3'b110;
        parameter [2:0] F3_BRANCH_BGEU = 3'b111;

        // OP_IMM指令的funct3
        parameter [2:0] F3_OP_IMM_ADDI  = 3'b000;
        parameter [2:0] F3_OP_IMM_SLTI  = 3'b010;
        parameter [2:0] F3_OP_IMM_SLTIU = 3'b011;
        parameter [2:0] F3_OP_IMM_XORI  = 3'b100;
        parameter [2:0] F3_OP_IMM_ORI   = 3'b110;
        parameter [2:0] F3_OP_IMM_ANDI  = 3'b111;
        parameter [2:0] F3_OP_IMM_SLLI  = 3'b001;
        parameter [2:0] F3_OP_IMM_SRLI  = 3'b101;
        parameter [2:0] F3_OP_IMM_SRAI  = 3'b101;  // 与SRLI相同，通过funct7区分

        // OP指令的funct3
        parameter [2:0] F3_OP_ADD  = 3'b000;
        parameter [2:0] F3_OP_SUB  = 3'b000;  // 与ADD相同，通过funct7区分
        parameter [2:0] F3_OP_SLL  = 3'b001;
        parameter [2:0] F3_OP_SLT  = 3'b010;
        parameter [2:0] F3_OP_SLTU = 3'b011;
        parameter [2:0] F3_OP_XOR  = 3'b100;
        parameter [2:0] F3_OP_SRL  = 3'b101;
        parameter [2:0] F3_OP_SRA  = 3'b101;  // 与SRL相同，通过funct7区分
        parameter [2:0] F3_OP_OR   = 3'b110;
        parameter [2:0] F3_OP_AND  = 3'b111;

        // ========== funct7 参数 ==========
        parameter [6:0] F7_NORMAL = 7'b0000000;
        parameter [6:0] F7_ALT    = 7'b0100000;  // 用于SUB/SRA/SRAI

        `include "../sequence/instr_transaction.sv"
        `include "../sequence/sequence.sv"
        `include "../config/instr_config.sv"
        `include "../component/sequencer.sv"
        `include "../component/driver.sv"
        `include "../component/monitor.sv"
        `include "../component/ref_model.sv"
        `include "../component/scoreboard.sv"
        // `include "../component/coverage.sv"
        `include "../component/agent.sv"
endpackage
