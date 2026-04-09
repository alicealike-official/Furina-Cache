interface ID_interface(
        input clock
);
        logic [31:0] instruction;
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd;
        logic [31:0] imm;


        logic jump;
        logic branch;
        logic [1:0] alu_src_A_select;
        logic [2:0] alu_src_B_select;
        logic csr_write_enable;
        logic register_file_write;
        logic [2:0] register_file_write_data_select;
        logic memory_read;
        logic memory_write;

endinterface
