class coverage_collector extends uvm_subscriber #(instr_transaction);
    `uvm_component_utils(coverage_collector)
    
    // opcode覆盖率
    covergroup opcode_cg;
        coverpoint tx.instruction[6:0] {
            bins opcodes[] = {
                `OPCODE_LUI, `OPCODE_AUIPC, `OPCODE_JAL, `OPCODE_JALR,
                `OPCODE_BRANCH, `OPCODE_LOAD, `OPCODE_STORE, `OPCODE_ITYPE,
                `OPCODE_RTYPE, `OPCODE_FENCE, `OPCODE_ENVIRONMENT
            };
            illegal_bins illegal = {[7'h2B:7'h6F]};
        }
   endgroup
    
    // funct3覆盖率
    covergroup funct3_cg;
        coverpoint tx.instruction[14:12];
   endgroup
    
    // CSR指令funct3覆盖率
    covergroup csr_funct3_cg;
        coverpoint tx.instruction[14:12] {
            bins csr_ops[] = {1,2,3,4,5}; // CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
        }
   endgroup
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        opcode_cg = new();
        funct3_cg = new();
        csr_funct3_cg = new();
    endfunction
    
    function void write(instr_transaction t);
        tx = t;
        opcode_cg.sample();
        funct3_cg.sample();
        if (tx.instruction[6:0] == `OPCODE_ENVIRONMENT)
            csr_funct3_cg.sample();
    endfunction
endclass
