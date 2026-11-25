class dcache_probe_test extends dcache_scenario_test;
    `uvm_component_utils(dcache_probe_test)
    function new(string name = "dcache_probe_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.enable_probes = 1;
    endfunction
    // 外部数据检查完成后，再逐项核对内部场景发生次数；实现不等于覆盖。
    task run_probe_scenario(dcache_probe_sequence seq);
        int actual;
        run_scenario(seq);
        foreach (seq.required_probe_hits[label]) begin
            actual = env.probe_monitor.hits.exists(label) ? env.probe_monitor.hits[label] : 0;
            if (actual < seq.required_probe_hits[label]) begin
                `error($sformatf("%s observed=%0d required=%0d", label, actual,
                    seq.required_probe_hits[label]), "DCACHE_PROBE_MISSING")
            end
            `info($sformatf("%s=%0d required=%0d", label, actual,
                seq.required_probe_hits[label]), "DCACHE_PROBE_COVERAGE")
        end
    endtask
endclass
