// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_freeze_context_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_freeze_context_sequence)
    function new(string name = "dcache_freeze_context_sequence");
        super.new(name);
    endfunction
    // 让紧随写请求的读冻结数百拍，再检查恢复后仍使用正确的旁路数据。
    task body();
        cfg.continuous_cpu = 1;
        access(address(0,1));
        cfg.cpu_write_ready = 0;
        // 四笔命中写填满当前响应容量；紧随的读在队满前被接收，下一拍Stage2受阻。
        fork
            begin
                for (int index = 0; index < 4; index++) access(address(0,1),1,'h12000000+index,0);
                access(address(0,1),0,0,0);
            end
            begin
                obs.wait_cycles(320);
                cfg.cpu_write_ready = 1;
            end
        join
        finish_scenario();
        record_check("hundreds of frozen cycles",probe_monitor.max_freeze,256,1);
        required_probe_hits["frozen_r1_refresh"] = 256;
        required_probe_hits["frozen_bypass_context"] = 1;
        required_probe_hits["bypass_after_freeze"] = 1;
    endtask
endclass
