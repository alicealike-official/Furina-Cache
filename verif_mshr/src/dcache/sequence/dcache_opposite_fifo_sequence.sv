// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_opposite_fifo_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_opposite_fifo_sequence)
    function new(string name = "dcache_opposite_fifo_sequence");
        super.new(name);
    endfunction
    // 分别填满读或写响应队列，确认另一类型CPU请求也按规格受到反压。
    task body();
        access(address(0,1));
        for (int mode = 0; mode < 2; mode++) begin
            cfg.cpu_read_ready = mode != 0;
            cfg.cpu_write_ready = mode == 0;
            fork
                begin
                    // 先填满一类响应FIFO，再提交另一种请求，避免只验证同类型阻塞。
                    for (int index = 0; index < 4; index++) access(address(0,1,index),mode==1,'h34560000+index,0);
                    obs.wait_cycles(8);
                access(address(0,1,7),mode==0,'habcdef01,0);
                end
                begin
                    obs.wait_cycles(128);
                    cfg.cpu_read_ready = 1;
                    cfg.cpu_write_ready = 1;
                end
            join
            obs.wait_empty();
        end
        finish_scenario();
        required_probe_hits["read_full_blocks_write_cpu"] = 1;
        required_probe_hits["write_full_blocks_read_cpu"] = 1;
    endtask
endclass
