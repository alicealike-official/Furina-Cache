class instr_config extends uvm_object;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    `uvm_object_utils_begin(instr_config)
        `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_ALL_ON)
    `uvm_object_utils_end
    
    function new(string name = "instr_config");
        super.new(name);
    endfunction
endclass