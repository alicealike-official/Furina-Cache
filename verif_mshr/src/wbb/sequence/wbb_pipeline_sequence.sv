// 用四个流水批次覆盖连续输入、满槽停顿恢复，以及空闲后的单笔和短批次。
// 每笔仍是完整写回；这里只生成和安排输入，接口驱动由同一个driver完成。
class wbb_pipeline_sequence extends wbb_scenario_sequence;
    typedef wbb_activity_monitor::activity_snapshot_t activity_snapshot_t;
    localparam int WRITEBACK_COUNT = 2 * WBB_ENTRIES + 5;
    localparam int MIN_STALL_CYCLES = 4;
    localparam int GAP_CYCLES = 3;

    activity_snapshot_t starts[4];
    activity_snapshot_t ends[4];
    activity_snapshot_t idle_starts[2];
    activity_snapshot_t idle_ends[2];

    `uvm_object_utils(wbb_pipeline_sequence)

    function new(string name = "wbb_pipeline_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task run_continuous_batch(int batch_index, int first_index, int count, bit hold_responses);
    extern task run_stalled_batch();
    extern task run_idle_gap(int gap_index);
endclass

task wbb_pipeline_sequence::body();
    if (WBB_ENTRIES < 2) begin
        `fatal("Pipeline overlap requires at least two WBB entries", "WBB_PIPELINE_CONFIG")
    end
    run_continuous_batch(0, 0, WBB_ENTRIES, 1);
    run_stalled_batch();
    run_idle_gap(0);
    run_continuous_batch(2, 2 * WBB_ENTRIES + 2, 1, 0);
    run_idle_gap(1);
    run_continuous_batch(3, 2 * WBB_ENTRIES + 3, 2, 0);
endtask

// 提交一个不需要等待空槽的批次，保存开始和全部响应结束后的事件计数。
// 第一批暂停响应以保证先用完N个槽；后面的短批次正常响应，检查尾部结束和再次启动。
task wbb_pipeline_sequence::run_continuous_batch(int batch_index, int first_index, int count,
    bit hold_responses);
    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = !hold_responses;

    // 保存起点后提交流水批次，响应门控决定是否先占满所有槽。
    starts[batch_index] = obs.snapshot();
    send_pipeline_batch(first_index, count);

    // 提交结束后放行响应，排空并保存终点计数。
    obs.wait_cycles(1);
    cfg.mem_response_enable = 1;
    obs.wait_until_empty();
    ends[batch_index] = obs.snapshot();
endtask

// 提交N+2笔，让第N+1笔遇到满槽；另一个控制分支等N笔已发送，再保持至少4拍后放行响应。
// FIFO持续放行多个旧响应，保证恢复后还能再次出现旧push与新reserve同拍。
task wbb_pipeline_sequence::run_stalled_batch();
    int send_target;

    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 0;

    // 记录起点和发送目标，接下来两个分支分别提交批次与控制响应。
    starts[1] = obs.snapshot();
    send_target = obs.send_count + WBB_ENTRIES;

    // 批次超过槽数会等待；另一个分支在满槽保持规定拍数后解除等待。
    fork
        send_pipeline_batch(WBB_ENTRIES, WBB_ENTRIES + 2);
        begin
            obs.wait_for_sends(send_target);
            obs.wait_cycles(MIN_STALL_CYCLES);
            cfg.mem_response_enable = 1;
        end
    join

    // 等待最后的发送/响应完成，保存整批结束状态。
    obs.wait_until_empty();
    ends[1] = obs.snapshot();
endtask

// 在已完成响应的两批之间插入空闲，并单独保存计数，供test检查没有残留reserve或push。
task wbb_pipeline_sequence::run_idle_gap(int gap_index);
    idle_starts[gap_index] = obs.snapshot();
    idle_cycles(GAP_CYCLES);
    idle_ends[gap_index] = obs.snapshot();
endtask
