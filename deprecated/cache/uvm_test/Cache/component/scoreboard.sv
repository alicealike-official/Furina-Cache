class ID_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(instr_transaction, ID_scoreboard) instr_analysis_imp;
    
    local int match_count;
    local int mismatch_count;
    local instr_transaction actual_queue[$];
    local instr_transaction expected_queue[$];
    `uvm_component_utils(ID_scoreboard)
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
        instr_analysis_imp = new("instr_analysis_imp", this);
        match_count = 0;
        mismatch_count = 0;
    endfunction
    extern function void write(instr_transaction tr);
    extern function bit compare_transactions(instr_transaction tr1, instr_transaction tr2);
    extern function void compare_queues_fifo();
    extern function void report_phase(uvm_phase phase);
endclass

function void ID_scoreboard::write(instr_transaction tr);
       `uvm_info("SCB_WRITE", 
                  $sformatf("ID Stage received: instr=%h, opcode=%h", 
                            tr.instruction, tr.opcode), 
                  UVM_HIGH)
        if (tr == null) begin
            `uvm_error("SCB_NULL", "Received null transaction in write()")
            return;
        end
        actual_queue.push_back(tr);
        ID_ref_model::predict_decoder_output(
            tr.instruction,
            tr.opcode,
            tr.funct3,
            tr.funct7,
            tr.rs1,
            tr.rs2,
            tr.rd,
            tr.immediate
        );
        ID_ref_model::predict_cu_output(
            tr.opcode,
            tr.funct3,
            tr.jump,
            tr.alu_src_A_select,
            tr.branch,
            tr.alu_src_B_select,
            tr.csr_write_enable,
            tr.register_file_write,
            tr.register_file_write_data_select,
            tr.memory_read,
            tr.memory_write
        );
        expected_queue.push_back(tr);
        compare_queues_fifo();

endfunction


    // ==================================================
    // 方法1：顺序比较（FIFO模式）
    // ==================================================
    function void ID_scoreboard::compare_queues_fifo();
        instr_transaction exp_tr, act_tr;
        
        while (expected_queue.size() > 0 && actual_queue.size() > 0) begin
            // 从两个队列各取一个
            exp_tr = expected_queue.pop_front();
            act_tr = actual_queue.pop_front();
            
            // 比较
            if (!exp_tr.compare(act_tr)) begin
                `uvm_error("QUEUE_CMP", 
                          $sformatf("Mismatch at position %0d", match_count + mismatch_count))
                mismatch_count++;
            end else begin
                match_count++;
            end
        end
        
        // 检查剩余
        if (expected_queue.size() > 0) begin
            `uvm_error("QUEUE_EXP", 
                      $sformatf("Expected queue still has %0d items", expected_queue.size()))
        end
        
        if (actual_queue.size() > 0) begin
            `uvm_error("QUEUE_ACT", 
                      $sformatf("Actual queue still has %0d items", actual_queue.size()))
        end
    endfunction

    function void ID_scoreboard::report_phase(uvm_phase phase);
        `uvm_info("ID_scoreboard", 
                  $sformatf("Matches: %0d, Mismatches: %0d", 
                            match_count, mismatch_count), 
                  UVM_MEDIUM)
    endfunction
