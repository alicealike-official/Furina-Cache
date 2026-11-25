class dcache_base_sequence extends uvm_sequence #(dcache_transaction);
    `uvm_object_utils(dcache_base_sequence)
    function new(string name = "dcache_base_sequence");
        super.new(name);
    endfunction
    // 提交一笔整字请求，等待接受后即可发送下一笔，不等待该笔响应。
    task submit(bit [31:0] addr, bit is_write, bit [31:0] data, bit [4:0] id);
        dcache_transaction item;
        item = dcache_transaction::type_id::create("request");
        start_item(item);
        item.addr = addr;
        item.is_write = is_write;
        item.data = data;
        item.id = id;
        finish_item(item);
    endtask
endclass
