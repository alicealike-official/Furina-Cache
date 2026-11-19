// 检查同时存在N个待发槽时的逐槽服务、连续发送和轮询回绕。
class wbb_arbitration_test extends wbb_base_test;
    `uvm_component_utils(wbb_arbitration_test)

    function new(string name = "wbb_arbitration_test",
        uvm_component parent = null);
        super.new(name, parent);
    endfunction

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task run_sequence();
    extern function void check_send_burst(wbb_arbitration_sequence seq);
endclass

function void wbb_arbitration_test::build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.mem_max_pending = WBB_ENTRIES;
    cfg.mem_write_latency_cycles = 2;
    cfg.mem_random_ready = 0;
    cfg.mem_random_latency = 0;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_send_enable = 1;
    cfg.mem_response_enable = 0;
endfunction

// sequence先积累整组候选，再统一放行；test检查实际候选数和放行后的发送记录。
task wbb_arbitration_test::run_sequence();
    wbb_arbitration_sequence seq;

    seq = wbb_arbitration_sequence::type_id::create("seq");
    run_scenario(seq, wbb_arbitration_sequence::WRITEBACK_COUNT);
    check_count("pending candidates before release", seq.pending_before_release, WBB_ENTRIES);
    check_count("observed pending slots", env.activity.max_pending, WBB_ENTRIES, 1);
    check_count("continuous send burst", env.activity.max_send_burst, WBB_ENTRIES, 1);
    check_count("round-robin wrap", env.activity.rr_wrap_count, 1, 1);
    check_send_burst(seq);
endtask

// 检查统一放行后的N笔发送：每个槽只出现一次，相邻握手相差1拍，期间确有末槽到首槽回绕。
function void wbb_arbitration_test::check_send_burst(wbb_arbitration_sequence seq);
    bit [WBB_ENTRIES-1:0] seen;
    int id;
    int wraps;

    seen = '0;
    wraps = 0;
    if (env.activity.send_ids.size() < seq.burst_start + WBB_ENTRIES ||
        env.activity.send_cycles.size() < seq.burst_start + WBB_ENTRIES) begin
        `error("Arbitration burst records are incomplete", "WBB_ARBITRATION_RECORDS")
        return;
    end
    for (int index = 0; index < WBB_ENTRIES; index++) begin
        id = env.activity.send_ids[seq.burst_start + index];
        if (id < 0 || id >= WBB_ENTRIES || seen[id]) begin
            `error($sformatf("Invalid or repeated send ID %0d in burst", id), "WBB_ARBITRATION_ID")
        end else begin
            seen[id] = 1;
        end
        if (index > 0) begin
            check_count("arbitration send spacing",
                int'(env.activity.send_cycles[seq.burst_start + index] -
                    env.activity.send_cycles[seq.burst_start + index - 1]), 1);
            if (env.activity.send_ids[seq.burst_start + index - 1] == WBB_ENTRIES - 1 && id == 0) begin
                wraps++;
            end
        end
    end
    check_count("slots sent in released burst", $countones(seen), WBB_ENTRIES);
    check_count("last-to-first wrap inside burst", wraps, 1, 1);
    `info($sformatf("pending=%0d burst=%0d slots=%b wraps=%0d", seq.pending_before_release,
        WBB_ENTRIES, seen, wraps), "WBB_ARBITRATION_COVERAGE")
endfunction
