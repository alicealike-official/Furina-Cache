class instr_transaction extends uvm_sequence_item;
        rand bit [31:0] instruction;
        rand instr_type_e instr_type;
        rand bit [6:0] opcode;
        rand bit [4:0] rs1;
        rand bit [4:0] rs2;
        rand bit [4:0] rd;
        rand bit [2:0] funct3;
        rand bit [6:0] funct7;
        rand bit [31:0] immediate;
        //    rand bit write_done;
        //    rand bit trap_done;
        //    rand bit csr_ready;

        //-----------------ID stage signal------------------//
        bit jump;
        bit branch;
        bit [1:0] alu_src_A_select;
        bit [2:0] alu_src_B_select;
        bit csr_write_enable;
        bit register_file_write;
        bit [2:0] register_file_write_data_select;
        bit memory_read;
        bit memory_write;
//        bit pc_stall;
        //-----------------ID stage signal------------------//

        `uvm_object_utils_begin(instr_transaction)
        //`uvm_field_int(jump, UVM_ALL_ON)
        //`uvm_field_int(branch, UVM_ALL_ON)
        //`uvm_field_int(alu_src_A_select, UVM_ALL_ON)
       // `uvm_field_int(alu_src_B_select, UVM_ALL_ON)
        //`uvm_field_int(csr_write_enable, UVM_ALL_ON)
        //`uvm_field_int(register_file_write, UVM_ALL_ON)
        //`uvm_field_int(register_file_write_data_select, UVM_ALL_ON)
        //`uvm_field_int(memory_read, UVM_ALL_ON)
        //`uvm_field_int(memory_write, UVM_ALL_ON)
        `uvm_field_int(instruction, UVM_ALL_ON)
        //        `uvm_field_int(write_done, UVM_ALL_ON)
        //        `uvm_field_int(trap_done, UVM_ALL_ON)
        //        `uvm_field_int(csr_ready, UVM_ALL_ON)
        `uvm_object_utils_end


        constraint valid_registers {
                rs1 inside {[0:31]};
                rs2 inside {[0:31]};
                rd inside {[0:31]};
        }

        constraint instr_encoding {
                solve instr_type before opcode, funct3, funct7, immediate;

                if (instr_type == INSTR_TYPE_R) {
                        opcode inside {OPCODE_OP};
                        immediate == 0;
                }
                else if (instr_type == INSTR_TYPE_I) {
                        opcode inside {OPCODE_OP_IMM, OPCODE_LOAD, OPCODE_JALR};
                        rs2 == 0;
                }
                else if (instr_type == INSTR_TYPE_S) {
                        opcode == OPCODE_STORE;
                        rd == 0;
                }
                else if (instr_type == INSTR_TYPE_B) {
                        opcode == OPCODE_BRANCH;
                        rd == 0;
                        //immediate[0] == 0;  // Align
                        immediate[11:0] inside {[-2048:2047]};
                }
                else if (instr_type == INSTR_TYPE_U) {
                        opcode inside {OPCODE_LUI, OPCODE_AUIPC};
                        rs1 == 0;
                        rs2 == 0;
                        funct3 == 0;
                        immediate[11:0] == 0;  
                }
                else if (instr_type == INSTR_TYPE_J) {
                        opcode == OPCODE_JAL;
                        rs1 == 0;
                        rs2 == 0;
                        funct3 == 0;
                        //immediate[0] == 0;  //Align
                        immediate[19:0] inside {[-524288:524287]};
                }
        }

        constraint valid_funct3 {
                solve opcode before funct3;

                if (opcode == OPCODE_LOAD) {
                        funct3 inside {
                                F3_LOAD_LB, F3_LOAD_LH, F3_LOAD_LW, 
                                F3_LOAD_LBU, F3_LOAD_LHU
                        };
                }
                else if (opcode == OPCODE_STORE) {
                        funct3 inside {F3_STORE_SB, F3_STORE_SH, F3_STORE_SW};
                }
                else if (opcode == OPCODE_BRANCH) {
                        funct3 inside {
                                F3_BRANCH_BEQ, F3_BRANCH_BNE, F3_BRANCH_BLT,
                                F3_BRANCH_BGE, F3_BRANCH_BLTU, F3_BRANCH_BGEU
                        };
                }
                else if (opcode inside {OPCODE_OP_IMM}) {
                        funct3 inside {F3_OP_IMM_ADDI ,
                                F3_OP_IMM_SLTI ,
                                F3_OP_IMM_SLTIU,
                                F3_OP_IMM_XORI ,
                                F3_OP_IMM_ORI  ,
                                F3_OP_IMM_ANDI ,
                                F3_OP_IMM_SLLI ,
                                F3_OP_IMM_SRLI ,
                                F3_OP_IMM_SRAI 
                        };
                }
                else if (opcode inside { OPCODE_OP}) {
                        funct3 inside {
                                F3_OP_ADD ,
                                F3_OP_SUB ,
                                F3_OP_SLL ,
                                F3_OP_SLT ,
                                F3_OP_SLTU,
                                F3_OP_XOR ,
                                F3_OP_SRL ,
                                F3_OP_SRA ,
                                F3_OP_OR  ,
                                F3_OP_AND 
                        };
                }
                else if (opcode inside {OPCODE_JAL, OPCODE_JALR, OPCODE_LUI, OPCODE_AUIPC}) {
                        funct3 == 3'b000;
                }
        }

        //        constraint valid_addr_constraint {
        //                if (funct3 == F3_STORE_SB) {
        //                        (rs1 + immediate) % 2 == 0;
        //                }
        //
        //                if (funct3 == F3_STORE_SH) {
        //                        (rs1 + immediate) % 4 == 0;
        //                }
        //                if (funct3 == F3_STORE_SW) {
        //                        (rs1 + immediate) % 8 == 0;
        //                }
        //        }

        constraint funct7_constraint {
                if (opcode == OPCODE_OP) {
                        if (funct3 == F3_OP_SUB || funct3 == F3_OP_SRA) {
                                funct7 inside { 7'b0100000};
                        } 
                        else {
                                funct7 == 7'b0000000;
                        }
                }

                        else if (opcode == OPCODE_OP_IMM) {
                                if (funct3 == F3_OP_IMM_SRAI) {
                                        funct7 inside {7'b0100000};
                                } 
                                else {
                                        funct7 == 0;
                                }
                        }
                                else {
                                        funct7 == 0;
                                }
        }


        function new(string name = "rv32i_instr");
                super.new(name);
        endfunction

        extern function void to_bits();
        extern function string get_mnemonic();
        extern function string convert2string();
        extern virtual function void do_copy(uvm_object rhs);
            // 随机化后自动调用post_randomize
        extern function void post_randomize();
        extern function bit do_compare(uvm_object rhs, uvm_comparer comparer);
endclass

function void instr_transaction::to_bits();
        case (instr_type)
                INSTR_TYPE_R: begin
                        instruction = {funct7, rs2, rs1, funct3, rd, opcode};
                end
                INSTR_TYPE_I: begin
                        instruction = {immediate[11:0], rs1, funct3, rd, opcode};
                end
                INSTR_TYPE_S: begin
                        instruction = {immediate[11:5], rs2, rs1, funct3, immediate[4:0], opcode};
                end
                INSTR_TYPE_B: begin
                        instruction = {immediate[12], immediate[10:5], rs2, rs1, funct3, 
                                immediate[4:1], immediate[11], opcode};
                end
                INSTR_TYPE_U: begin
                        instruction = {immediate[31:12], rd, opcode};
                end
                INSTR_TYPE_J: begin
                        instruction = {immediate[20], immediate[10:1], immediate[11], 
                                immediate[19:12], rd, opcode};
                end
        endcase
endfunction

function string instr_transaction::get_mnemonic();
        string mnemonic;

        case (opcode)
                OPCODE_LUI:   mnemonic = "LUI";
                OPCODE_AUIPC: mnemonic = "AUIPC";
                OPCODE_JAL:   mnemonic = "JAL";
                OPCODE_JALR:  mnemonic = "JALR";

                OPCODE_BRANCH: begin
                        case (funct3)
                                F3_BRANCH_BEQ:  mnemonic = "BEQ";
                                F3_BRANCH_BNE:  mnemonic = "BNE";
                                F3_BRANCH_BLT:  mnemonic = "BLT";
                                F3_BRANCH_BGE:  mnemonic = "BGE";
                                F3_BRANCH_BLTU: mnemonic = "BLTU";
                                F3_BRANCH_BGEU: mnemonic = "BGEU";
                                default: mnemonic = "UNKNOWN";
                        endcase
                end

                OPCODE_LOAD: begin
                        case (funct3)
                                F3_LOAD_LB:  mnemonic = "LB";
                                F3_LOAD_LH:  mnemonic = "LH";
                                F3_LOAD_LW:  mnemonic = "LW";
                                F3_LOAD_LBU: mnemonic = "LBU";
                                F3_LOAD_LHU: mnemonic = "LHU";
                                default: mnemonic = "UNKNOWN";
                        endcase
                end

                OPCODE_STORE: begin
                        case (funct3)
                                F3_STORE_SB: mnemonic = "SB";
                                F3_STORE_SH: mnemonic = "SH";
                                F3_STORE_SW: mnemonic = "SW";
                                default: mnemonic = "UNKNOWN";
                        endcase
                end

                OPCODE_OP_IMM: begin
                        case (funct3)
                                F3_OP_IMM_ADDI  :   mnemonic = "ADDI";
                                F3_OP_IMM_SLLI  :   mnemonic = "SLLI";
                                F3_OP_IMM_SLTI  :   mnemonic = "SLTI";
                                F3_OP_IMM_SLTIU :   mnemonic = "SLTIU";
                                F3_OP_IMM_XORI  :   mnemonic = "XORI";
                                F3_OP_IMM_ORI   :   mnemonic = "ORI";
                                F3_OP_IMM_ANDI  :   mnemonic = "ANDI";
                                F3_OP_IMM_SLLI  :   mnemonic = "SLLI";
                                F3_OP_IMM_SRLI  :   mnemonic = "SRLI";
                                F3_OP_IMM_SRAI  :   mnemonic = "SRAI";
                                default:    mnemonic = "UNKNOWN";
                        endcase
                end

                OPCODE_OP: begin
                        case (funct3)
                                F3_OP_ADD  : mnemonic = "ADD";
                                F3_OP_SUB  : mnemonic = "SUB";
                                F3_OP_SLL  : mnemonic = "SLL";
                                F3_OP_SLT  : mnemonic = "SLT";
                                F3_OP_SLTU : mnemonic = "SLTU";
                                F3_OP_XOR  : mnemonic = "XOR";
                                F3_OP_SRL  : mnemonic = "SRL";
                                F3_OP_SRA  : mnemonic = "SRA";
                                F3_OP_OR   : mnemonic = "OR";
                                F3_OP_AND  : mnemonic = "AND";
                                default:    mnemonic = "UNKNOWN";
                        endcase
                end

                default: mnemonic = "UNKNOWN";
        endcase

        return mnemonic;
endfunction

function string instr_transaction::convert2string();
        return $sformatf("%s: instr=0x%08h", 
                get_mnemonic(), instruction);
endfunction

function void instr_transaction::do_copy(uvm_object rhs);
        instr_transaction tr_copy;

        // 检查类型
        if (!$cast(tr_copy, rhs)) begin
                `uvm_fatal("COPY", "Wrong type in do_copy")
                return;
        end

        // 复制所有字段
        super.do_copy(rhs);  // 调用父类
        instruction = tr_copy.instruction;
        opcode = tr_copy.opcode;
        rs1 = tr_copy.rs1;
        rs2 = tr_copy.rs2;
        rd = tr_copy.rd;
        funct3 = tr_copy.funct3;
        funct7 = tr_copy.funct7;
        immediate = tr_copy.immediate;
        instr_type = tr_copy.instr_type;
        jump = tr_copy.jump;
        branch = tr_copy.branch;
        alu_src_A_select = tr_copy.alu_src_A_select;
        alu_src_B_select = tr_copy.alu_src_B_select;
        csr_write_enable = tr_copy.csr_write_enable;
        register_file_write = tr_copy.register_file_write;
        register_file_write_data_select = tr_copy.register_file_write_data_select;
        memory_read = tr_copy.memory_read;
        memory_write = tr_copy.memory_write;
        `uvm_info("COPY", "Transaction copied", UVM_HIGH)
endfunction

function void instr_transaction::post_randomize();
        super.post_randomize();
        // 确保instruction正确
        to_bits();  // 调用to_bits更新instruction
endfunction


    function bit instr_transaction::do_compare(uvm_object rhs, uvm_comparer comparer);
        instr_transaction tr;
        bit match;
        
        // 类型转换
        if (!$cast(tr, rhs)) begin
            `uvm_error("CMP_CAST", "Failed to cast to instr_transaction")
            return 0;
        end
        
        // 调用父类比较
        match = super.do_compare(rhs, comparer);
        
        match &= (this.instr_type == tr.instr_type);
        match &= (this.opcode == tr.opcode);
        match &= (this.rs1 == tr.rs1);
        match &= (this.rs2 == tr.rs2);
        match &= (this.rd == tr.rd);
        match &= (this.funct3 == tr.funct3);
        match &= (this.funct7 == tr.funct7);
        match &= (this.immediate == tr.immediate);

        match &= (this.jump == tr.jump);
        match &= (this.branch == tr.branch);
        match &= (this.alu_src_A_select == tr.alu_src_A_select);
        match &= (this.alu_src_B_select == tr.alu_src_B_select);
        match &= (this.csr_write_enable == tr.csr_write_enable);
        match &= (this.register_file_write == tr.register_file_write);
        match &= (this.register_file_write_data_select == tr.register_file_write_data_select);
        match &= (this.memory_read == tr.memory_read);
        match &= (this.memory_write == tr.memory_write);
        return match;
    endfunction