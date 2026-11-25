// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_fifo_policy_edges_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_fifo_policy_edges_sequence)
    function new(string name = "dcache_fifo_policy_edges_sequence");
        super.new(name);
    endfunction
    // 改变实际fill先后并保持部分way锁定，核对FIFO跳锁及无效路优先。
    task body();
        cfg.read_response_enable = 0;
        for (int tag = 1; tag <= 4; tag++) access(address(0,tag),0,0,0);
        obs.wait_cycles(16);
        cfg.response_order = 1;
        finish_scenario();
        // 逆序fill形成非数字递增的FIFO偏好；锁住最老候选，再触发下一个victim选择。
        cfg.read_response_enable = 0;
        access(address(0,5),0,0,0);
        access(address(0,6),0,0,0);
        access(address(1,1),0,0,0);
        access(address(1,2),0,0,0);
        finish_scenario();
        required_probe_hits["policy_skips_lock"] = 1;
        required_probe_hits["free_way_with_locks"] = 1;
        required_probe_hits["policy_fill_checked"] = 8;
    endtask
endclass
