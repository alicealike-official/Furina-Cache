// 一项代表一笔CPU整字请求；item_done仅表示DUT接受，不代表CPU响应完成。
class dcache_transaction extends uvm_sequence_item;
    bit idle_payload = 0;
    rand bit [31:0] addr;
    rand bit is_write;
    rand bit [31:0] data;
    rand bit [4:0] id;
    constraint aligned { addr[1:0] == 0; }
    `uvm_object_utils_begin(dcache_transaction)
        `uvm_field_int(idle_payload, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(is_write, UVM_DEFAULT)
        `uvm_field_int(data, UVM_DEFAULT)
        `uvm_field_int(id, UVM_DEFAULT)
    `uvm_object_utils_end
    function new(string name = "dcache_transaction");
        super.new(name);
    endfunction
endclass
