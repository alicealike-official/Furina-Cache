// riscv_pkg.sv
package riscv_pkg;
    // 操作码定义
    parameter OPCODE_RTYPE     = 7'b0110011;  // R-type
    parameter OPCODE_ITYPE     = 7'b0010011;  // I-type
    parameter OPCODE_LOAD      = 7'b0000011;  // Load
    parameter OPCODE_STORE     = 7'b0100011;  // Store
    parameter OPCODE_BRANCH    = 7'b1100011;  // Branch
    parameter OPCODE_JAL       = 7'b1101111;  // JAL
    parameter OPCODE_JALR      = 7'b1100111;  // JALR
    parameter OPCODE_AUIPC     = 7'b0010111;  // AUIPC
    parameter OPCODE_LUI       = 7'b0110111;  // LUI
    parameter OPCODE_ENVIRONMENT = 7'b1110011; // CSR
    
    // R-type funct3
    parameter RTYPE_ADDSUB = 3'b000;
    parameter RTYPE_SLL    = 3'b001;
    parameter RTYPE_SLT    = 3'b010;
    parameter RTYPE_SLTU   = 3'b011;
    parameter RTYPE_XOR    = 3'b100;
    parameter RTYPE_SR     = 3'b101;
    parameter RTYPE_OR     = 3'b110;
    parameter RTYPE_AND    = 3'b111;
    
    // I-type funct3
    parameter ITYPE_ADDI  = 3'b000;
    parameter ITYPE_SLLI  = 3'b001;
    parameter ITYPE_SLTI  = 3'b010;
    parameter ITYPE_SLTIU = 3'b011;
    parameter ITYPE_XORI  = 3'b100;
    parameter ITYPE_SRXI  = 3'b101;
    parameter ITYPE_ORI   = 3'b110;
    parameter ITYPE_ANDI  = 3'b111;
    
    // Branch funct3
    parameter BRANCH_BEQ  = 3'b000;
    parameter BRANCH_BNE  = 3'b001;
    parameter BRANCH_BLT  = 3'b100;
    parameter BRANCH_BGE  = 3'b101;
    parameter BRANCH_BLTU = 3'b110;
    parameter BRANCH_BGEU = 3'b111;
    
    // CSR funct3
    parameter CSR_CSRRW  = 3'b001;
    parameter CSR_CSRRS  = 3'b010;
    parameter CSR_CSRRC  = 3'b011;
    parameter CSR_CSRRWI = 3'b101;
    parameter CSR_CSRRSI = 3'b110;
    parameter CSR_CSRRCI = 3'b111;
    
    // ALU操作码
    parameter ALU_OP_ADD = 4'b0000;
    parameter ALU_OP_SUB = 4'b0001;
    parameter ALU_OP_AND = 4'b0010;
    parameter ALU_OP_OR  = 4'b0011;
    parameter ALU_OP_XOR = 4'b0100;
    parameter ALU_OP_SLT = 4'b0101;
    parameter ALU_OP_SLTU= 4'b0110;
    parameter ALU_OP_SLL = 4'b0111;
    parameter ALU_OP_SRL = 4'b1000;
    parameter ALU_OP_SRA = 4'b1001;
    parameter ALU_OP_ABJ = 4'b1010;
    parameter ALU_OP_BPA = 4'b1011;
    parameter ALU_OP_NOP = 4'b1111;
endpackage