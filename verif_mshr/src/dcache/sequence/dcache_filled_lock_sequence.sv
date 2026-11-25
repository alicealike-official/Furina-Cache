class dcache_filled_lock_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_filled_lock_sequence)
    function new(string name = "dcache_filled_lock_sequence");
        super.new(name);
    endfunction
    // 在已fill但replay未完成时访问同块，检查仍锁定的行不能作为普通命中。
    task body();
        int before_reads;
        access(address(0,1));
        cfg.read_response_enable = 0;
        cfg.cpu_read_ready = 0;
        for (int word = 0; word < 4; word++) access(address(1,1,word),0,0,0);
        for (int word = 0; word < 4; word++) access(address(0,1,word),0,0,0);
        wait_probe("read_fifo_full",1);
        cfg.read_response_enable = 1;
        wait_probe("fill_while_locked",2);
        before_reads = obs.reads;
        fork
            access(address(1,1,5),0,0,0);
            begin
                obs.wait_cycles(32);
                cfg.cpu_read_ready = 1;
            end
        join
        finish_scenario();
        record_check("filled locked address needs no new fetch",obs.reads-before_reads,0);
        required_probe_hits["filled_locked_cpu_query"] = 1;
    endtask
endclass
