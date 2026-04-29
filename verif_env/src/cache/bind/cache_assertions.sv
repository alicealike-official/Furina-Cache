// bind_assertions.sv
`ifndef BIND_CACHE_ASSERTIONS_SV
`define BIND_CACHE_ASSERTIONS_SV
// `include "uvm_macros.svh"
// import uvm_pkg::*;
module cache_assertions (
    cache_debug_interface dbg_if
);


    // ===================== 断言1: 复位后 valid 全0 =====================
    // 在复位释放后的第一个时钟沿，所有 valid 位必须为 0。
    generate
    genvar i,j;
    for(i=0;i<`NUM_CACHE_WAY;i++) begin
        for(j=0;j<`NUM_CACHE_SET;j++) begin

            // reset拉低瞬间
            assert property (
                @(negedge dbg_if.reset) ##1 (dbg_if.valid[i][j] == 0)
            ) else
                $error("Async reset failed valid[%0d][%0d]",i,j);

            // reset保持期间
            assert property (
                @(posedge dbg_if.clk) !dbg_if.reset |-> (dbg_if.valid[i][j] == 0)
            ) else
                $error( "Reset hold failed valid[%0d][%0d]",i,j);

        end
    end
    endgenerate

    // ===================== 断言2: Fetch（缓存行填充）后 valid 置1 =====================
    // 当 miss_done 信号为高时（表示从内存读取完成并写入cache line），对应的 way 的 valid 应被置1。
    // 注意：miss_done 在 D_cache 中是一拍脉冲，我们在下一个时钟沿检查 valid 被置1。
    // 还需要注意curr_alloc_way和index_in的值，应该保持为条件发生时的只，因为操作符号|=>要延迟到下一拍检查
    generate
        for(j=0;j<`NUM_CACHE_SET;j++) begin : MISS_VALID
            assert property (@(posedge dbg_if.clk)
                $rose(dbg_if.miss_done)
                |=> dbg_if.valid[
                        $past(dbg_if.curr_alloc_way)
                    ][
                        $past(dbg_if.index_in)
                    ]
            ) else $error("VALID not set after miss refill");
        end
    endgenerate

    // ===================== 断言3: dirty条件监测 =====================
    // 目前只有三种操作需要改变dirty，一种是写命中是dirty由0变为1，一种是写回的时候，dirty位清零，
    // 最后一种是在写操作下写回后从内存读取数据时，又将dirty变为1
    generate
    

    for(i = 0; i < `NUM_CACHE_WAY; i++) begin : WAY_GEN
        for(j = 0; j < `NUM_CACHE_SET; j++) begin : SET_GEN
            property p_dirty_change_has_reason;
            @(posedge dbg_if.clk)
            disable iff(!dbg_if.reset)
            (dbg_if.dirty[i][j] != $past(dbg_if.dirty[i][j]))
            |->
            (
                ($past(dbg_if.cpu_req_handshake) && $past(dbg_if.cpu_wr_en) && $past(dbg_if.hit_sign) 
                && $past(dbg_if.hit_way == i) && $past(dbg_if.index_in == j))
                ||
                ($past(dbg_if.wb_done) && $past(dbg_if.curr_alloc_way == i) && $past(dbg_if.index_in == j))
                ||
                ($past(dbg_if.miss_done) && $past(dbg_if.cpu_wr_en) 
                && $past(dbg_if.curr_alloc_way == i) && $past(dbg_if.index_in == j))
            );
            endproperty

            assert property(p_dirty_change_has_reason) else $error("Dirty unchanged when condition comes!!!");
        end
    end
    endgenerate

    // ===================== 断言4: 同一地址不会出现在多个 Way 中 =====================
    // 对于同一个 index，不能有两个不同的 way 同时 valid 且 tag 相等。
    // 这需要在每次 valid 或 tag 变化时检查。
    // generate
    //     for (i = 0; i < `NUM_CACHE_WAY; i++) begin : gen_i
    //         for (j = i+1; j < `NUM_CACHE_WAY; j++) begin : gen_j
    //             assert property (
    //                 @(posedge dbg_if.clk) disable iff (!dbg_if.reset)
    //                 (dbg_if.valid[i][*] && dbg_if.valid[j][*]) && (dbg_if.tag[i][*] == dbg_if.tag[j][*])
    //                 |-> 0;
    //             ) else $error("Same tag appears in two ways for same index");
    //         end
    //     end
    // endgenerate

genvar s;
generate
    for (s = 0; s < `NUM_CACHE_SET; s++) begin : gen_set
        for (i = 0; i < `NUM_CACHE_WAY; i++) begin : gen_i
            for (j = i+1; j < `NUM_CACHE_WAY; j++) begin : gen_j

                assert property (
                    @(posedge dbg_if.clk)
                    disable iff (!dbg_if.reset)

                    !(
                        dbg_if.valid[i][s] &&
                        dbg_if.valid[j][s] &&
                        (dbg_if.tag[i][s] == dbg_if.tag[j][s])
                    )

                ) else
                    $error("Duplicate tag in set=%0d between way=%0d and way=%0d",
                           s, i, j);

            end
        end
    end
endgenerate


//============================================================
// Assertion: 仅当 victim 为 dirty 且 valid 时，替换阶段才允许发起写回
// 含义：mem写请求(mem_req_valid && mem_wr_en) 不能无故发生，
//      必须由一次 dirty victim eviction 导致
//============================================================

// 建议前提：dbg_if中可观察以下信号：
// curr_state, DIRTY_CHECK, curr_alloc_way, index_in
// valid[][], dirty[][]
// mem_req_valid, mem_wr_en
//
// writeback触发点按你的RTL：
// write_req_condition = (curr_state == DIRTY_CHECK && is_dirty)
//
// 所以当写请求真正发起时，上一个周期必须满足：
// state == DIRTY_CHECK
// victim valid == 1
// victim dirty == 1

property p_writeback_only_when_dirty_evicted;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    // 当前拍真正发起写回请求
    (dbg_if.mem_req_valid && dbg_if.mem_wr_en)

    |->
    
    // 上一拍必须是在检查一个有效脏块
    (
        $past(dbg_if.curr_state == 2'b01) &&

        $past(
            dbg_if.valid[
                dbg_if.curr_alloc_way
            ][
                dbg_if.index_in
            ]
        ) &&

        $past(
            dbg_if.dirty[
                dbg_if.curr_alloc_way
            ][
                dbg_if.index_in
            ]
        )
    );

endproperty

assert property (p_writeback_only_when_dirty_evicted)
    else $error("Illegal writeback: mem write issued without dirty victim eviction");

//============================================================
// Cache CPU / Memory Interface Protocol Assertions
// 适配你当前D_cache接口语义：
// CPU:
//   req handshake  = cpu_req_valid && cpu_req_ready
//   resp handshake = cpu_resp_valid && cpu_resp_ready
//
// Memory:
//   req handshake  = mem_req_valid && mem_req_ready
//   resp handshake = mem_resp_valid && mem_resp_ready
//
// 核心原则：
// 1. valid拉高后直到ready前必须保持
// 2. 握手完成后状态推进
// 3. 不允许无请求乱响应（按你的单事务模型）
//============================================================


//============================================================
// 一、CPU接口协议
//============================================================


//------------------------------------------------------------
// CPU-1:
// 当CPU请求被阻塞时（valid=1 ready=0），
// 请求信息必须保持稳定
//------------------------------------------------------------
property p_cpu_req_stable_when_stall;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.cpu_req_valid && !dbg_if.cpu_req_ready)

    |-> 

    (
        dbg_if.cpu_req_valid &&
        $stable(dbg_if.cpu_wr_en)   &&
        $stable(dbg_if.cpu_req_addr)&&
        $stable(dbg_if.cpu_wdata)
    );
endproperty

assert property (p_cpu_req_stable_when_stall)
    else $error("CPU request changed while stalled");


//------------------------------------------------------------
// CPU-2:
// cache响应valid拉高后，若CPU未ready，响应必须保持
//------------------------------------------------------------
property p_cpu_resp_stable_when_wait;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.cpu_resp_valid && !dbg_if.cpu_resp_ready)

    |=>

    (
        dbg_if.cpu_resp_valid &&
        $stable(dbg_if.cache_rdata)
    );
endproperty

assert property (p_cpu_resp_stable_when_wait)
    else $error("CPU response changed while waiting for cpu_resp_ready");


//------------------------------------------------------------
// CPU-3:
// 单请求模型下，非IDLE时不应继续接受新请求
//------------------------------------------------------------
property p_cpu_no_accept_when_busy;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.curr_state != 2'b00)

    |->

    (!dbg_if.cpu_req_ready);
endproperty

assert property (p_cpu_no_accept_when_busy)
    else $error("Cache accepted CPU request while busy");



//============================================================
// 二、Memory Request接口协议
//============================================================


//------------------------------------------------------------
// MEM-1:
// mem_req_valid拉高后直到握手完成前，
// 地址/类型/数据必须稳定
//------------------------------------------------------------
property p_mem_req_stable_when_stall;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.mem_req_valid && !dbg_if.mem_req_ready)

    |=>

    (
        dbg_if.mem_req_valid &&
        $stable(dbg_if.mem_wr_en) &&
        $stable(dbg_if.mem_addr)  &&
        $stable(dbg_if.mem_wdata)
    );
endproperty

assert property (p_mem_req_stable_when_stall)
    else $error("Memory request changed before handshake");


//------------------------------------------------------------
// MEM-2:
// 写请求与读请求互斥（mem_wr_en定义操作方向）
// 实际上这里只检查X态/非法态
//------------------------------------------------------------
property p_mem_wr_en_known;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    dbg_if.mem_req_valid |-> !$isunknown(dbg_if.mem_wr_en);
endproperty

assert property (p_mem_wr_en_known)
    else $error("mem_wr_en unknown during mem request");



//============================================================
// 三、Memory Response接口协议
//============================================================


//------------------------------------------------------------
// MEM-3:
// Cache只有在WB/MISS_WAIT时才能接收mem response
//------------------------------------------------------------
property p_mem_resp_only_when_expected;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.mem_resp_valid)

    |->

    (dbg_if.curr_state == 2'b10 ||
     dbg_if.curr_state == 2'b11);
endproperty

assert property (p_mem_resp_only_when_expected)
    else $error("Unexpected memory response received");


//------------------------------------------------------------
// MEM-4:
// mem_resp_valid高但cache未ready时，
// memory返回数据必须保持稳定
//------------------------------------------------------------
property p_mem_resp_stable_when_stall;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.mem_resp_valid && !dbg_if.mem_resp_ready)

    |=>

    (
        dbg_if.mem_resp_valid &&
        $stable(dbg_if.mem_rdata)
    );
endproperty

assert property (p_mem_resp_stable_when_stall)
    else $error("Memory response changed while stalled");



//============================================================
// 四、请求-响应配对（单Outstanding模型）
//============================================================


//------------------------------------------------------------
// MEM-5:
// 发起mem request后最终应收到response
// （可根据最大latency加bounded delay，如##[1:50]）
//------------------------------------------------------------
property p_mem_req_eventually_get_resp;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.mem_req_valid && dbg_if.mem_req_ready)

    |->

    ##[1:$] (dbg_if.mem_resp_valid && dbg_if.mem_resp_ready);
endproperty

assert property (p_mem_req_eventually_get_resp)
    else $error("Memory request never got response");


//------------------------------------------------------------
// MEM-6:
// 无mem request outstanding时，不应平白收到response
// 若你有pending标志最好用pending，没有的话弱化版如下：
//------------------------------------------------------------
property p_no_spurious_mem_resp;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (dbg_if.curr_state == 2'b00)

    |->

    !dbg_if.mem_resp_valid;
endproperty

assert property (p_no_spurious_mem_resp)
    else $error("Spurious memory response while cache idle");


//============================================================
// Cache Latency Assertions
// 基于你当前RTL：
// cpu_req_ready = (curr_state == IDLE)
// cpu_resp_valid = (curr_state == IDLE && hit_sign) || miss_done
//
// 关键理解：
// 1. 命中：请求握手当拍即可响应（组合命中）
// 2. 未命中：必须等待mem返回完成后才能cpu_resp_valid
//
// 若你后续改成寄存输出，周期数需调整
//============================================================



//============================================================
// 一、命中延迟（Hit Latency）
//============================================================

//------------------------------------------------------------
// HIT-1:
// 在IDLE状态下，CPU请求被接受且命中时，
// 同拍必须给出cpu_resp_valid
//
// 因为：
// cpu_req_handshake = valid && ready
// ready=1 only in IDLE
// cpu_resp_valid = IDLE && hit_sign
//------------------------------------------------------------
property p_hit_resp_immediate;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (
        dbg_if.curr_state == 2'b00 &&
        dbg_if.cpu_req_valid &&
        dbg_if.cpu_req_ready &&
        dbg_if.hit_sign
    )

    |->

    dbg_if.cpu_resp_valid;
endproperty

assert property (p_hit_resp_immediate)
    else $error("Hit latency violation: hit request did not respond immediately");



//------------------------------------------------------------
// HIT-2:
// 命中请求不应进入MISS路径
//------------------------------------------------------------
property p_hit_no_miss_transition;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (
        dbg_if.curr_state == 2'b00 &&
        dbg_if.cpu_req_valid &&
        dbg_if.cpu_req_ready &&
        dbg_if.hit_sign
    )

    |=>

    (dbg_if.curr_state == 2'b00);
endproperty

assert property (p_hit_no_miss_transition)
    else $error("Hit request incorrectly entered miss flow");



//============================================================
// 二、未命中延迟（Miss Latency）
//============================================================

//------------------------------------------------------------
// MISS-1:
// 请求miss后，下一拍必须离开IDLE进入DIRTY_CHECK
//------------------------------------------------------------
property p_miss_enter_miss_flow;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (
        dbg_if.curr_state == 2'b00 &&
        dbg_if.cpu_req_valid &&
        dbg_if.cpu_req_ready &&
        !dbg_if.hit_sign
    )

    |=>

    (dbg_if.curr_state == 2'b01);
endproperty

assert property (p_miss_enter_miss_flow)
    else $error("Miss latency violation: miss did not enter DIRTY_CHECK");



//------------------------------------------------------------
// MISS-2:
// 从miss请求被接受开始，
// 在mem响应完成前，不允许cpu_resp_valid提前出现
//
// until_with:
// 左边条件持续成立直到右边发生
//------------------------------------------------------------
property p_miss_no_early_cpu_response;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (
        dbg_if.curr_state == 2'b01 &&
        dbg_if.cpu_req_valid &&
        dbg_if.cpu_req_ready &&
        !dbg_if.hit_sign
    )

    |=>

    (
        (!dbg_if.cpu_resp_valid)[*0:$]
        ##1
        (dbg_if.mem_resp_valid && dbg_if.mem_resp_ready)
    );
endproperty

assert property (p_miss_no_early_cpu_response)
    else $error("Miss latency violation: cpu responded before memory completed");



//------------------------------------------------------------
// MISS-3:
// mem响应完成后，下一拍必须cpu_resp_valid
//
// 注意：
// 你的miss_done定义：
// miss_done = (curr_state == MISS_WAIT && mem_resp_handshake)
//
// cpu_resp_valid = miss_done
//
// 因此通常是同拍。
// 如果你未来改寄存器输出，把 |-> 改 |=>
//------------------------------------------------------------
property p_miss_resp_after_mem_done;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (
        dbg_if.curr_state == 2'b11 &&
        dbg_if.mem_resp_valid &&
        dbg_if.mem_resp_ready
    )

    |->

    dbg_if.cpu_resp_valid;
endproperty

assert property (p_miss_resp_after_mem_done)
    else $error("Miss latency violation: no CPU response when miss completed");



//------------------------------------------------------------
// MISS-4:
// Miss期间cache不应接受新CPU请求
//------------------------------------------------------------
property p_miss_busy_blocks_cpu;
    @(posedge dbg_if.clk)
    disable iff (!dbg_if.reset)

    (
        dbg_if.curr_state != 2'b00
    )

    |->

    !dbg_if.cpu_req_ready;
endproperty

assert property (p_miss_busy_blocks_cpu)
    else $error("Miss flow violation: cache accepted new CPU request while busy");
endmodule
`endif
