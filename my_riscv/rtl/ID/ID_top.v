`include "../define/define.vh"
module ID_top(
        input [31:0] instruction,

        output reg [6:0] opcode,
        output reg [2:0] funct3,
        output reg [6:0] funct7,
        output reg [4:0] rs1,
        output reg [4:0] rs2,
        output reg [4:0] rd,
        output reg [31:0] imm,

        output reg jump,
        output reg branch,
        output reg [1:0] alu_src_A_select,
        output reg [2:0] alu_src_B_select,
        output reg csr_write_enable,
        output reg register_file_write,
        output reg [2:0] register_file_write_data_select,
        output reg memory_read,
        output reg memory_write
);

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

        ControlUnit u_ControlUnit(
                .opcode(opcode),
                .funct3(funct3),
                .jump(jump),
                .branch(branch),
                .alu_src_A_select(alu_src_A_select),
                .alu_src_B_select(alu_src_B_select),
                .csr_write_enable(csr_write_enable),
                .register_file_write(register_file_write),
                .register_file_write_data_select(register_file_write_data_select),
                .memory_read(memory_read),
                .memory_write(memory_write)
        );

        InstructionDecoder u_InstructionDecoder(
                .instruction(instruction),
                .opcode(opcode),
                .funct3(funct3),
                .funct7(funct7),
                .rs1(rs1),
                .rs2(rs2),
                .rd(rd),
                .imm(imm)
        );
endmodule

