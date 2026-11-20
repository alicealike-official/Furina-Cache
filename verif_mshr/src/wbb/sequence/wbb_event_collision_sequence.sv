// 串行模式分别安排两事件同拍；流水模式安排三个、四个不同槽的事件同拍。
class wbb_event_collision_sequence extends wbb_scenario_sequence;
    localparam int WRITEBACK_COUNT = 6;
    localparam int PIPELINE_WRITEBACK_COUNT = 7;

    `uvm_object_utils(wbb_event_collision_sequence)

    function new(string name = "wbb_event_collision_sequence");
        super.new(name);
    endfunction

    extern virtual task body();
    extern task prepare_old_write(int index, output int id);
    extern function void select_response(int id);
    extern task drain_stage();
    extern task collide_with_reserve();
    extern task collide_with_push();
    extern task collide_with_send();
    extern task collide_pipeline(bit include_send, int first_index);
endclass

task wbb_event_collision_sequence::body();
    if (WBB_ENTRIES < 2) begin
        `fatal("Different-slot collisions require at least two slots", "WBB_CASE_CONFIG")
    end
    if (cfg.input_mode == WBB_INPUT_PIPELINE) begin
        if (WBB_ENTRIES < 4) begin
            `fatal("Four simultaneous events require at least four WBB slots", "WBB_CASE_CONFIG")
        end
        collide_pipeline(0, 0);
        collide_pipeline(1, 3);
    end else begin
        collide_with_reserve();
        collide_with_push();
        collide_with_send();
    end
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
endtask

// 先准备旧在途写回，再提交两笔流水写回；首笔预留后放行旧响应。
// include_send=1时另留一笔待发送候选，同拍放开ready，形成旧响应、候选发送、首笔push和后笔reserve四事件重叠。
// 四个事件分别使用沿前处于issued、pending、reserved、free的槽，不借用本拍刚释放的槽。
task wbb_event_collision_sequence::collide_pipeline(bit include_send, int first_index);
    int old_id;
    int pipeline_first;
    int reserve_target;
    int response_target;

    // 先准备旧在途写回；四事件场景再额外保留一个待发送候选。
    prepare_old_write(first_index, old_id);
    pipeline_first = first_index + 1;
    if (include_send) begin
        cfg.mem_send_enable = 0;
        send_line(pipeline_first);
        pipeline_first++;
        obs.wait_cycles(1);
    end

    // 记录事件目标，两个分支分别提交流水事务与对齐旧响应/发送。
    reserve_target = obs.reserve_count + 1;
    response_target = obs.response_count + 1;
    fork
        send_pipeline_batch(pipeline_first, 2);
        begin
            obs.wait_for_reserves(reserve_target);
            select_response(old_id);
            cfg.mem_send_enable = 1;
            obs.wait_for_responses(response_target);
            cfg.mem_response_enable = 0;
        end
    join

    // 目标交叉发生后再放行剩余事务，避免影响下一子场景。
    drain_stage();
endtask

// 先提交旧写回并等其发送，再留出到期时间；返回时位于采样沿，可安排下一拍的交叉事件。
task wbb_event_collision_sequence::prepare_old_write(int index, output int id);
    int send_start;

    send_start = obs.send_count;
    send_line(index);
    obs.wait_for_sends(send_start + 1);
    obs.wait_cycles(2);
    id = obs.send_ids[send_start];
endtask

// 选择一个已经发送的ID，允许memory driver在下一下降沿准备其响应；调用方保证处于采样沿。
function void wbb_event_collision_sequence::select_response(int id);
    cfg.mem_response_order = WBB_MEM_SELECTED;
    cfg.mem_selected_response_id = id;
    cfg.mem_response_enable = 1;
endfunction

// 完成当前子场景的全部剩余响应，再暂停新响应选择，供下一个独立子场景使用。
task wbb_event_collision_sequence::drain_stage();
    obs.wait_cycles(1);
    cfg.mem_send_enable = 1;
    cfg.mem_response_order = WBB_MEM_FIFO;
    cfg.mem_response_enable = 1;
    obs.wait_until_empty();
    cfg.mem_response_enable = 0;
endtask

// 同一采样沿启动新写回并允许旧响应，下一下降沿两个driver分别准备reserve和response。
task wbb_event_collision_sequence::collide_with_reserve();
    int old_id;

    prepare_old_write(0, old_id);
    select_response(old_id);
    send_line(1);
    drain_stage();
endtask

// 等新写回实际reserve成功后再允许旧响应，使下一拍的push与旧响应握手同时发生。
task wbb_event_collision_sequence::collide_with_push();
    int old_id;
    int reserve_target;
    int response_target;

    prepare_old_write(2, old_id);
    reserve_target = obs.reserve_count + 1;
    response_target = obs.response_count + 1;
    fork
        send_line(3);
        begin
            obs.wait_for_reserves(reserve_target);
            select_response(old_id);
            obs.wait_for_responses(response_target);
            cfg.mem_response_enable = 0;
        end
    join
    drain_stage();
endtask

// 先让新行处于待发状态，再同拍打开send接收和旧响应，得到不同槽的send/response交叉。
task wbb_event_collision_sequence::collide_with_send();
    int old_id;
    int response_target;

    prepare_old_write(4, old_id);
    cfg.mem_send_enable = 0;
    send_line(5);
    obs.wait_cycles(2);
    response_target = obs.response_count + 1;
    select_response(old_id);
    cfg.mem_send_enable = 1;
    obs.wait_for_responses(response_target);
    cfg.mem_response_enable = 0;
    drain_stage();
endtask
