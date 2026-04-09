class ID_monitor extends uvm_monitor;
        virtual ID_interface ID_vif;
        uvm_analysis_port #(instr_transaction) ap_instr;

        `uvm_component_utils(ID_monitor)

        function new(string name, uvm_component parent);
                super.new(name, parent);
                ap_instr = new("ap_instr", this);
        endfunction

        function void build_phase(uvm_phase phase);
                if(!uvm_config_db#(virtual ID_interface)::get(this, "", "ID_vif", ID_vif))
                        `uvm_fatal("MON", "Failed to get interface")
        endfunction

        task run_phase(uvm_phase phase);
                instr_transaction instr_tr;
                forever begin
                        @(posedge ID_vif.clock);
                        instr_tr = instr_transaction::type_id::create("instr_tr");
                        instr_tr.instruction = ID_vif.instruction;
                        instr_tr.jump = ID_vif.jump;
                        instr_tr.branch = ID_vif.branch;
                        instr_tr.alu_src_A_select = ID_vif.alu_src_A_select;
                        instr_tr.alu_src_B_select = ID_vif.alu_src_B_select;
                        instr_tr.csr_write_enable = ID_vif.csr_write_enable;
                        instr_tr.register_file_write = ID_vif.register_file_write;
                        instr_tr.register_file_write_data_select = ID_vif.register_file_write_data_select;
                        instr_tr.memory_read = ID_vif.memory_read;
                        instr_tr.memory_write = ID_vif.memory_write;
                        instr_tr.opcode = ID_vif.opcode;
                        instr_tr.funct3 = ID_vif.funct3;
                        instr_tr.funct7 = ID_vif.funct7;
                        instr_tr.rs1 = ID_vif.rs1;
                        instr_tr.rs2 = ID_vif.rs2;
                        instr_tr.rd = ID_vif.rd;
                        instr_tr.immediate = ID_vif.imm;
                        ap_instr.write(instr_tr);
                end
        endtask
endclass
