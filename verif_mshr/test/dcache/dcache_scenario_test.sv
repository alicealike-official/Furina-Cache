// 所有公开IO case共用计数和命中判定；激励数据与调度保留在sequence。
class dcache_scenario_test extends dcache_base_test;
    `uvm_component_utils(dcache_scenario_test)
    function new(string name = "dcache_scenario_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg.timeout_cycles = 4000000;
        cfg.request_timeout_cycles = 10000;
    endfunction
    // 启动场景并统一核对实际CPU完成及所有阶段要求；原C++和IO SVA持续检查。
    task run_scenario(dcache_scenario_sequence seq);
        int actual;
        seq.start(env.agent.sequencer);
        wait_for_drain();
        check_count("generated requests", env.activity.requests, seq.submitted);
        check_count("completed requests", env.activity.responses, seq.submitted);
        foreach (seq.checks[index]) begin
            if ((seq.checks[index].at_least && seq.checks[index].actual < seq.checks[index].expected) ||
                (!seq.checks[index].at_least && seq.checks[index].actual != seq.checks[index].expected)) begin
                `error($sformatf("%s actual=%0d expected%s%0d", seq.checks[index].label,
                    seq.checks[index].actual, seq.checks[index].at_least ? ">=" : "=", seq.checks[index].expected), "DCACHE_SCENARIO")
            end
        end
        foreach (seq.required_hits[label]) begin
            actual = env.activity.hits.exists(label) ? env.activity.hits[label] : 0;
            if (actual < seq.required_hits[label]) begin
                `error($sformatf("%s actual=%0d required>=%0d", label, actual, seq.required_hits[label]), "DCACHE_COVERAGE_MISSING")
            end
            `info($sformatf("%s=%0d required=%0d", label, actual, seq.required_hits[label]), "DCACHE_EVENT_COVERAGE")
        end
        `info($sformatf("requests=%0d responses=%0d memory_reads=%0d memory_writes=%0d checks=%0d",
            env.activity.requests, env.activity.responses, env.activity.reads, env.activity.writes,
            seq.checks.size()), "DCACHE_SCENARIO_COVERAGE")
    endtask
endclass
