// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_reallocation_versions_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_reallocation_versions_sequence)
    function new(string name = "dcache_reallocation_versions_sequence");
        super.new(name);
    endfunction
    // 反复驱逐、重新分配并同字覆盖写，检查各次读值和实际后端写回。
    task body();
        // 每轮先驱逐再冷写，W-W-R按CPU接受顺序保持最后版本，随后再驱逐核对后端。
        for (int round_index = 0; round_index < 4; round_index++) begin
            evict_set(0);
            cfg.continuous_cpu = 1;
            access(address(0,1),1,'h77000000+round_index,0);
            access(address(0,1),1,'h88000000+round_index,0);
            access(address(0,1),0,0,0);
            obs.wait_empty();
            evict_set(0);
            check_evicted_set(0,1,1);
        end
        finish_scenario();
    endtask
endclass
