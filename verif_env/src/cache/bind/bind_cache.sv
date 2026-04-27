`include "define.svh"
bind D_cache cache_debug_interface u_dbg_if(
    .clk(clk),
    .reset(reset),
    .valid(valid),
    .dirty(dirty),
    .tag(tag),
    .cache_data(cache_data),
    .alloc_way(alloc_way)
);