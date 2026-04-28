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

    // ===================== 断言3: 读操作不置脏 =====================
    // 当发生读命中（hit_sign && !cpu_wr_en）时，dirty 位不应改变。
    // 我们需要捕获读命中时刻的 dirty 值，并在之后一个周期检查不变。
    // 由于 dirty 可能在同周期被写操作影响，我们检查在握手完成后的下一个时钟沿 dirty 未被写1。
    // 更好的方式：在读命中且握手成功时，dirty 必须等于之前的值。
    // 这里简化：在读命中且握手完成时，dirty 不应从0变成1。
    // property p_read_no_dirty;
    //     @(posedge clk) (
    //         cpu_req_handshake && hit_sign && !cpu_wr_en
    //     ) |-> 
    //         $stable(dirty[hit_way][index_in]);  // 该周期内 dirty 稳定不变
    // endproperty
    // assert property (p_read_no_dirty) else $error("Read hit: dirty bit changed unexpectedly");

    // ===================== 断言5: 写操作置脏 =====================
    // 写命中时，dirty 应变为1（如果原本是0）。写未命中时，填充后写数据也会置脏。
    // 现检查两种场景：
    // 1) 写命中：cpu_req_handshake && cpu_wr_en && hit_sign 时，下一个时钟沿 dirty[hit_way][index_in] == 1
    // 2) 写未命中且填充完成：miss_done && cpu_wr_en（由内部逻辑决定）时，dirty[curr_alloc_way][index_in] == 1
    // property p_write_set_dirty_hit;
    //     @(posedge clk) 
    //     (cpu_req_handshake && cpu_wr_en && hit_sign) |=> 
    //         dirty[hit_way][index_in] == 1'b1;
    // endproperty
    // assert property (p_write_set_dirty_hit) else $error("Write hit: dirty not set");

    // property p_write_set_dirty_miss;
    //     @(posedge clk) 
    //     (miss_done && cpu_wr_en) |=> 
    //         dirty[curr_alloc_way][index_in] == 1'b1;
    // endproperty
    // assert property (p_write_set_dirty_miss) else $error("Write miss: dirty not set after fill");

    // ===================== 断言6: 写回后清脏 =====================
    // 当 wb_done 信号有效（写回完成），且被写回的行之前是脏的，那么 dirty 应被清0。
    // 注意：wb_done 时，dirty 即被清除（设计中的 wb_done 触发 dirty 清0）。
    // property p_writeback_clear_dirty;
    //     @(posedge clk) $rose(wb_done) |=> 
    //         dirty[curr_alloc_way][index_in] == 1'b0;
    // endproperty
    // assert property (p_writeback_clear_dirty) else $error("Writeback: dirty not cleared after wb_done");

    // ===================== 断言7: 同一地址不会出现在多个 Way 中 =====================
    // 对于同一个 index，不能有两个不同的 way 同时 valid 且 tag 相等。
    // 这需要在每次 valid 或 tag 变化时检查。
    // property p_unique_tag_per_index;
    //     @(posedge clk) disable iff (!reset)
    //     (1) |-> 
    //         foreach (cache_way[i]) foreach (cache_way[j]) 
    //         (i != j && valid[i][index] && valid[j][index]) |-> (tag[i][index] != tag[j][index]);
    // endproperty
    // 由于 foreach 可能不支持，我们使用 generate 生成多个断言。
    // genvar i, j;
    // generate
    //     for (i = 0; i < Num_Cache_Way; i++) begin : gen_i
    //         for (j = i+1; j < Num_Cache_Way; j++) begin : gen_j
    //             assert property (
    //                 @(posedge clk) disable iff (!reset)
    //                 (valid[i][*] && valid[j][*] && (tag[i][*] == tag[j][*]))
    //                 |-> 0
    //             ) else $error("Same tag appears in two ways for same index");
    //         end
    //     end
    // endgenerate

endmodule

`endif