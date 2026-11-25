// 基础读、同字写、再读；只验证框架通路，不覆盖复杂淘汰和并发。
class dcache_smoke_sequence extends dcache_base_sequence;
    `uvm_object_utils(dcache_smoke_sequence)
    function new(string name = "dcache_smoke_sequence");
        super.new(name);
    endfunction
    task body();
        submit('h1000, 0, 0, 0);
        submit('h1000, 1, 'h12345678, 1);
        submit('h1000, 0, 0, 2);
    endtask
endclass
