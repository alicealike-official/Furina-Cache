class base_instr_sequence extends uvm_sequence #(instr_transaction);
    `uvm_object_utils(base_instr_sequence)
    
    function new(string name = "");
        super.new(name);
    endfunction
    
    virtual task body();
        instr_transaction tr;
        tr = instr_transaction::type_id::create("tr");
        if (!tr.randomize())
            `uvm_fatal("RAND", "Randomization failed!") // 打印此信息说明确实失败了
        start_item(tr);
        finish_item(tr);
    endtask
endclass

