// 在显式延迟模式下先延后单笔push，再批量预留所有槽，保持全reserved状态后逐笔push。
class wbb_delayed_push_sequence extends wbb_scenario_sequence;
    localparam int WRITEBACK_COUNT = WBB_ENTRIES + 1;
    localparam int SINGLE_PUSH_DELAY = 5;
    localparam int BATCH_HOLD_CYCLES = 6;

    `uvm_object_utils(wbb_delayed_push_sequence)

    function new(string name = "wbb_delayed_push_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
endclass

task wbb_delayed_push_sequence::body();
    if (!cfg.allow_delayed_push) begin
        `fatal("Recompile this case with WBB_ALLOW_DELAYED_PUSH", "WBB_DELAYED_MODE")
    end
    send_line(0, block_addr(0), block_addr(0), SINGLE_PUSH_DELAY);
    obs.wait_until_empty();
    cfg.mem_send_enable = 0;
    cfg.mem_response_enable = 0;

    send_batch(1, BATCH_HOLD_CYCLES, block_addr(1), block_addr(WBB_ENTRIES));
    obs.wait_cycles(2);
    cfg.mem_send_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
endtask
