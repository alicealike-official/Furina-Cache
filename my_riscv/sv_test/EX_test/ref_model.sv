// alu_ref_model.sv
import riscv_pkg::*;

class alu_ref_model;
    // 计算预期结果
    static function void calculate_expected(
        input [6:0] opcode,
        input [2:0] funct3,
        input funct7_5,
        input imm_10,
        input [31:0] src_A,
        input [31:0] src_B,
        input [31:0] pc,
        input [31:0] imm,
        input branch,
        input branch_estimation,
        
        output [31:0] exp_result,
        output exp_zero,
        output exp_branch_taken,
        output [31:0] exp_branch_target,
        output exp_prediction_miss
    );
        
        logic [3:0] alu_op;
        logic [31:0] alu_out;
        
        // 生成ALU操作码
        alu_op = generate_alu_op(opcode, funct3, funct7_5, imm_10);
        
        // 执行ALU运算
        alu_out = execute_alu(alu_op, src_A, src_B);
        
        // 分支逻辑
        if (branch) begin
            exp_branch_target = pc + imm;
            
            case (funct3)
                BRANCH_BEQ:  exp_branch_taken = (src_A == src_B);
                BRANCH_BNE:  exp_branch_taken = (src_A != src_B);
                BRANCH_BLT:  exp_branch_taken = ($signed(src_A) < $signed(src_B));
                BRANCH_BGE:  exp_branch_taken = ($signed(src_A) >= $signed(src_B));
                BRANCH_BLTU: exp_branch_taken = (src_A < src_B);
                BRANCH_BGEU: exp_branch_taken = (src_A >= src_B);
                default:     exp_branch_taken = 1'b0;
            endcase
            
            exp_prediction_miss = (branch_estimation != exp_branch_taken);
        end else begin
            exp_branch_taken = 1'b0;
            exp_branch_target = 32'b0;
            exp_prediction_miss = 1'b0;
        end
        
        exp_result = alu_out;
        exp_zero = (alu_out == 32'b0);
    endfunction
    
    // 生成ALU操作码
    static function [3:0] generate_alu_op(
        input [6:0] opcode,
        input [2:0] funct3,
        input funct7_5,
        input imm_10
    );
        case (opcode)
            OPCODE_AUIPC, OPCODE_JAL, OPCODE_JALR, OPCODE_LOAD, OPCODE_STORE: 
                return ALU_OP_ADD;
                
            OPCODE_BRANCH: begin
                case (funct3)
                    BRANCH_BEQ, BRANCH_BNE: return ALU_OP_SUB;
                    BRANCH_BLT, BRANCH_BGE: return ALU_OP_SLT;
                    BRANCH_BLTU, BRANCH_BGEU: return ALU_OP_SLTU;
                    default: return ALU_OP_NOP;
                endcase
            end
            
            OPCODE_ITYPE: begin
                case (funct3)
                    ITYPE_ADDI:  return ALU_OP_ADD;
                    ITYPE_SLLI:  return ALU_OP_SLL;
                    ITYPE_SLTI:  return ALU_OP_SLT;
                    ITYPE_SLTIU: return ALU_OP_SLTU;
                    ITYPE_XORI:  return ALU_OP_XOR;
                    ITYPE_SRXI:  return imm_10 ? ALU_OP_SRA : ALU_OP_SRL;
                    ITYPE_ORI:   return ALU_OP_OR;
                    ITYPE_ANDI:  return ALU_OP_AND;
                    default: return ALU_OP_NOP;
                endcase
            end
            
            OPCODE_RTYPE: begin
                case (funct3)
                    RTYPE_ADDSUB: return funct7_5 ? ALU_OP_SUB : ALU_OP_ADD;
                    RTYPE_SLL:    return ALU_OP_SLL;
                    RTYPE_SLT:    return ALU_OP_SLT;
                    RTYPE_SLTU:   return ALU_OP_SLTU;
                    RTYPE_XOR:    return ALU_OP_XOR;
                    RTYPE_SR:     return funct7_5 ? ALU_OP_SRA : ALU_OP_SRL;
                    RTYPE_OR:     return ALU_OP_OR;
                    RTYPE_AND:    return ALU_OP_AND;
                    default: return ALU_OP_NOP;
                endcase
            end
            
            OPCODE_ENVIRONMENT: begin
                case (funct3)
                    CSR_CSRRW, CSR_CSRRWI: return ALU_OP_BPA;
                    CSR_CSRRS, CSR_CSRRSI: return ALU_OP_OR;
                    CSR_CSRRC, CSR_CSRRCI: return ALU_OP_ABJ;
                    default: return ALU_OP_NOP;
                endcase
            end
            
            default: return ALU_OP_NOP;
        endcase
    endfunction
    
    // 执行ALU运算
    static function [31:0] execute_alu(
        input [3:0] alu_op,
        input [31:0] a,
        input [31:0] b
    );
        case (alu_op)
            ALU_OP_ADD:  return a + b;
            ALU_OP_SUB:  return a - b;
            ALU_OP_AND:  return a & b;
            ALU_OP_OR:   return a | b;
            ALU_OP_XOR:  return a ^ b;
            ALU_OP_SLT:  return ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_OP_SLTU: return (a < b) ? 32'd1 : 32'd0;
            ALU_OP_SLL:  return a << b[4:0];
            ALU_OP_SRL:  return a >> b[4:0];
            ALU_OP_SRA:  return $signed(a) >>> b[4:0];
            ALU_OP_ABJ:  return b & (~a);
            ALU_OP_BPA:  return a;
            default: return 32'b0;
        endcase
    endfunction
endclass