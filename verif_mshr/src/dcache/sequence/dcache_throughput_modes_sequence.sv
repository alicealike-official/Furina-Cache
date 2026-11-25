// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_throughput_modes_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_throughput_modes_sequence)
    function new(string name = "dcache_throughput_modes_sequence");
        super.new(name);
    endfunction
    // 分别测量连续读、连续写和混合命中流的实际接受拍数。
    task body();
        int first_request;
        cfg.continuous_cpu = 1;
        access(address(0,1));
        for (int mode = 0; mode < 3; mode++) begin
            obs.wait_empty();
            first_request = obs.requests;
            for (int index = 0; index < 128; index++) begin
                access(address(0,1,index%16),mode==1 || (mode==2 && index%2!=0),'h45670000+index,0);
            end
            obs.wait_empty();
            record_check("128 handshakes on consecutive cycles",
                int'(obs.cpu_cycles[first_request+127]-obs.cpu_cycles[first_request]),127);
        end
        finish_scenario();
    endtask
endclass
