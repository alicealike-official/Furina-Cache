class dcache_smoke_test extends dcache_base_test;
    `uvm_component_utils(dcache_smoke_test)
    function new(string name = "dcache_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    // 激励来自sequence，test只启动并核对两读一写的完整完成。
    virtual task run_sequence();
        dcache_smoke_sequence seq;
        // 【防御性检查】有激励的case要求active CPU agent。
        if (env.agent.sequencer == null) begin
            `fatal("Smoke requires an active CPU agent", "DCACHE_CONFIG")
        end
        seq = dcache_smoke_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        wait_for_drain();
        check_count("CPU requests", env.scoreboard.requests, 3);
        check_count("CPU read responses", env.scoreboard.read_responses, 2);
        check_count("CPU write responses", env.scoreboard.write_responses, 1);
    endtask
endclass
