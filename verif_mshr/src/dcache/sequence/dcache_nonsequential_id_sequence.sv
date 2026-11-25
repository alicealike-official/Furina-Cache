// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_nonsequential_id_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_nonsequential_id_sequence)
    function new(string name = "dcache_nonsequential_id_sequence");
        super.new(name);
    endfunction
    // 按非连续ID顺序反复写读，检查ID透传、数据匹配与完成后复用。
    task body();
        int order[8] = '{31,0,17,4,29,8,23,2};
        access(address(0,1));
        for (int round_index = 0; round_index < 8; round_index++) begin
            foreach (order[index]) begin
                next_id = order[index];
                access(address(0,1,index),1,'h87340000+round_index*16+index);
                next_id = order[(index+3)%8];
                access(address(0,1,index));
            end
        end
        finish_scenario();
        record_check("nonsequential ID transfers",obs.requests,129);
    endtask
endclass
