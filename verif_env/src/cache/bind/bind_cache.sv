`include "define.svh"
bind D_cache cache_debug_interface u_dbg_if(
    .clk(clk),
    .reset(reset),
    .valid(valid),
    .dirty(dirty),
    .tag(tag),
    .cache_data(cache_data),
    .alloc_way(alloc_way),
    .miss_done(miss_done),
    .index_in(index_in),
    .curr_alloc_way(curr_alloc_way)
);