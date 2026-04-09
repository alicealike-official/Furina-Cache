class ID_ref_model extends uvm_component;    
    `uvm_component_utils(ID_ref_model)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    extern static function void predict_decoder_output(
        input bit [31:0] instruction,
        output bit [6:0] opcode,
        output bit [2:0] funct3,
        output bit [6:0] funct7,
        output bit [4:0] rs1,
        output bit [4:0] rs2,
        output bit [4:0] rd,
        output bit [31:0] imm
    );

    extern static function void predict_cu_output(
        input bit [6:0] opcode,
        input bit [2:0] funct3,

        output bit jump,
        output bit [1:0] alu_src_A_select,
        output bit branch,
        output bit [2:0] alu_src_B_select,
        output bit csr_write_enable,
        output bit register_file_write,
        output bit [2:0] register_file_write_data_select,
        output bit memory_read,
        output bit memory_write
    );
endclass

// 参考模型：立即数生成器行为
static function void ID_ref_model::predict_decoder_output(
        input bit [31:0] instruction,
        output bit [6:0] opcode,
        output bit [2:0] funct3,
        output bit [6:0] funct7,
        output bit [4:0] rs1,
        output bit [4:0] rs2,
        output bit [4:0] rd,
        output bit [31:0] imm
    );
        bit [19:0] raw_imm;
        case (opcode)
            `OPCODE_LUI, `OPCODE_AUIPC: begin
                rd = instruction[11:7];
                raw_imm = instruction[31:12];
                funct3 = 3'b000;
                rs1 = 5'b0;
                rs2 = 5'b0;
                funct7 = 7'b0;
            end

            `OPCODE_JAL: begin
                rd = instruction[11:7];
                raw_imm = {instruction[31], instruction[19:12], 
                                 instruction[20], instruction[30:21]};
                funct3 = 3'b000;
                rs1 = 5'b0;
                rs2 = 5'b0;
                funct7 = 7'b0;
            end
            
            `OPCODE_JALR, `OPCODE_LOAD, `OPCODE_ITYPE, 
            `OPCODE_FENCE, `OPCODE_ENVIRONMENT: begin
                rd = instruction[11:7];
                funct3 = instruction[14:12];
                rs1 = instruction[19:15];
                raw_imm = {8'b0, instruction[31:20]};
                rs2 = 5'b0;
                funct7 = 7'b0;
            end
            `OPCODE_BRANCH: begin
                funct3 = instruction[14:12];
                rs1 = instruction[19:15];
                rs2 = instruction[24:20];
                raw_imm = {instruction[31], instruction[7], 
                                 instruction[30:25], instruction[11:8]};
                rd = 5'b0;
                funct7 = 7'b0;
            end
            `OPCODE_STORE: begin
                funct3 = instruction[14:12];
                rs1 = instruction[19:15];
                rs2 = instruction[24:20];
                raw_imm = {8'b0, instruction[31:25], instruction[11:7]};
                rd = 5'b0;
                funct7 = 7'b0;
            end
            `OPCODE_RTYPE: begin
                rd = instruction[11:7];
                funct3 = instruction[14:12];
                rs1 = instruction[19:15];
                rs2 = instruction[24:20];
                funct7 = instruction[31:25];
                raw_imm = 20'b0;
            end
            default: begin
                funct3 = 3'b0;
                funct7 = 7'b0;
                rs1 = 5'b0;
                rs2 = 5'b0;
                rd = 5'b0;
                raw_imm = 20'b0;
            end
        endcase

        //--------------generate imm------------------//
        case (opcode)
            `OPCODE_JALR, `OPCODE_LOAD, `OPCODE_ITYPE, 
            `OPCODE_FENCE, `OPCODE_ENVIRONMENT, `OPCODE_STORE: begin
                imm = {{20{raw_imm[11]}}, raw_imm[11:0]};
            end
            `OPCODE_LUI, `OPCODE_AUIPC: begin
                imm = {raw_imm, 12'b0};
            end
            `OPCODE_BRANCH: begin
                imm = {{19{raw_imm[11]}}, raw_imm[11:0], 1'b0};
            end
            `OPCODE_JAL: begin
                imm = {{11{raw_imm[19]}}, raw_imm[19:0], 1'b0};
            end
            default: imm = 32'b0;
        endcase
endfunction


    static function void ID_ref_model::predict_cu_output(
        input bit [6:0] opcode,
        input bit [2:0] funct3,

        output bit jump,
        output bit [1:0] alu_src_A_select,
        output bit branch,
        output bit [2:0] alu_src_B_select,
        output bit csr_write_enable,
        output bit register_file_write,
        output bit [2:0] register_file_write_data_select,
        output bit memory_read,
        output bit memory_write
    );
    //---------------------initial------------------------//
        //pc_stall = !write_done || !trap_done || !csr_ready;
        jump = 0;
        branch = 0;
        alu_src_A_select = `ALU_SRC_A_NONE;
        alu_src_B_select = `ALU_SRC_B_NONE;
        csr_write_enable = 0;
        register_file_write = 0;
        register_file_write_data_select = `RF_WD_NONE;
        memory_read = 0;
        memory_write = 0;
    //---------------------initial------------------------//


        case (opcode)
            `OPCODE_LUI: begin
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_LUI;
            end

            `OPCODE_AUIPC: begin
                alu_src_A_select = `ALU_SRC_A_PC;
                alu_src_B_select = `ALU_SRC_B_IMM;
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_ALU;
            end

            `OPCODE_JAL: begin
                jump = 1;
                alu_src_A_select = `ALU_SRC_A_PC;
                alu_src_B_select = `ALU_SRC_B_IMM;
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_JUMP;
            end

            `OPCODE_JALR: begin
                jump = 1;
                alu_src_A_select = `ALU_SRC_A_RD1;
                alu_src_B_select = `ALU_SRC_B_IMM;
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_JUMP;
            end

            `OPCODE_BRANCH: begin
                branch = 1;
                alu_src_A_select = `ALU_SRC_A_RD1;
                alu_src_B_select = `ALU_SRC_B_RD2;
            end

            `OPCODE_LOAD: begin
                alu_src_A_select = `ALU_SRC_A_RD1;
                alu_src_B_select = `ALU_SRC_B_IMM;
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_LOAD;
                memory_read = 1;
            end

            `OPCODE_STORE: begin
                alu_src_A_select = `ALU_SRC_A_RD1;
                alu_src_B_select = `ALU_SRC_B_IMM;
                memory_write = 1;
            end

            `OPCODE_ITYPE: begin
                alu_src_A_select = `ALU_SRC_A_RD1;
                alu_src_B_select = (funct3 == `ITYPE_SRXI) ? 
                                          `ALU_SRC_B_SHAMT : `ALU_SRC_B_IMM;
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_ALU;
            end

            `OPCODE_RTYPE: begin
                alu_src_A_select = `ALU_SRC_A_RD1;
                alu_src_B_select = `ALU_SRC_B_RD2;
                register_file_write = 1;
                register_file_write_data_select = `RF_WD_ALU;
            end

            `OPCODE_ENVIRONMENT: begin
                csr_write_enable = (funct3 != 0);
                if (funct3 == 0) begin
                    alu_src_A_select = `ALU_SRC_A_NONE;
                    alu_src_B_select = `ALU_SRC_B_NONE;
                    register_file_write = 0;
                end else begin
                    alu_src_B_select = (funct3 == `CSR_CSRRW || 
                                               funct3 == `CSR_CSRRWI) ? 
                                              `ALU_SRC_B_NONE : `ALU_SRC_B_CSR;
                    alu_src_A_select = (funct3 == `CSR_CSRRW || 
                                               funct3 == `CSR_CSRRS || 
                                               funct3 == `CSR_CSRRC) ? 
                                              `ALU_SRC_A_RD1 : `ALU_SRC_A_RS1;
                    register_file_write = 1;
                    register_file_write_data_select = `RF_WD_CSR;
                end
            end
        endcase
endfunction