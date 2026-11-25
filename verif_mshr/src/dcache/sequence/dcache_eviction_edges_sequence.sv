// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_eviction_edges_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_eviction_edges_sequence)
    function new(string name = "dcache_eviction_edges_sequence");
        super.new(name);
    endfunction
    // 安排连续脏淘汰及旧地址访问，检查预留到push窗口和整行数据归属。
    task body();
        dirty_set(0);
        dirty_set(1);
        // 先改变set1的FIFO顺序，让接下来的两个victim位于不同way。
        access(address(1,5));
        obs.wait_empty();
        cfg.continuous_cpu = 1;
        access(address(0,5),0,0,0);
        access(address(1,6),0,0,0);
        access(address(0,1),1,'hdead1234,0);
        access(address(0,1),0,0,0);
        finish_scenario();
        required_probe_hits["consecutive_dirty_evictions"] = 1;
        required_probe_hits["adjacent_r2_way_change"] = 1;
        required_probe_hits["reserved_address_query"] = 1;
    endtask
endclass
