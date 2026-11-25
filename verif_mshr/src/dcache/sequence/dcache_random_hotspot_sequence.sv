// 单独profile达到4096笔实际接受请求；原始数据及IP检查继续复用。
class dcache_random_hotspot_sequence extends dcache_random_sequence;
    `uvm_object_utils(dcache_random_hotspot_sequence)
    function new(string name = "dcache_random_hotspot_sequence");
        super.new(name);
        profile = 1;
        random_ids = 1;
        random_cpu_sink = 0;
    endfunction
endclass
