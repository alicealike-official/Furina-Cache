`include "define.svh"

// interface cache_debug_interface(
//     input logic clk,
//     input logic reset
// );

//     localparam Index_Width      = $clog2(`NUM_CACHE_SET);
//     localparam Offset_Width     = $clog2(`CACHE_BLOCK_SIZE);
//     localparam Way_Width        = $clog2(`NUM_CACHE_WAY);
//     localparam Tag_Width        = `DATA_ADDR_BUS - Offset_Width - Index_Width;
//     // ──── 观测 DUT 内部存储 ────
//     logic                                      valid    [`NUM_CACHE_WAY][`NUM_CACHE_SET];
//     logic                                      dirty    [`NUM_CACHE_WAY][`NUM_CACHE_SET];
//     logic [Tag_Width-1:0]                      tag      [`NUM_CACHE_WAY][`NUM_CACHE_SET];
//     logic [`DATA_WIDTH-1:0]                    cache_data     [`NUM_CACHE_WAY][`NUM_CACHE_SET][`WORDS_PER_BLOCK];

//     // 替换策略状态（FIFO 指针）
//     logic [Way_Width-1:0]                      alloc_way [`NUM_CACHE_SET];
//endinterface


// interface cache_debug_interface #(
//     parameter Index_Width  = $clog2(`NUM_CACHE_SET),
//     parameter Offset_Width = $clog2(`CACHE_BLOCK_SIZE),
//     parameter Way_Width    = $clog2(`NUM_CACHE_WAY),
//     parameter Tag_Width    = `DATA_ADDR_BUS - Offset_Width - Index_Width
// )(
//     input logic clk,
//     input logic reset,

//     input logic valid [`NUM_CACHE_WAY][`NUM_CACHE_SET],
//     input logic dirty [`NUM_CACHE_WAY][`NUM_CACHE_SET],
//     input logic [Tag_Width-1:0] tag [`NUM_CACHE_WAY][`NUM_CACHE_SET],
//     input logic [`DATA_WIDTH-1:0] cache_data [`NUM_CACHE_WAY][`NUM_CACHE_SET][`WORDS_PER_BLOCK],

//     input logic [Way_Width-1:0] alloc_way [`NUM_CACHE_SET]
// );

// endinterface

`include "define.svh"

interface cache_debug_interface(
    input logic clk,
    input logic reset,

    input logic valid [`NUM_CACHE_WAY][`NUM_CACHE_SET],
    input logic dirty [`NUM_CACHE_WAY][`NUM_CACHE_SET],

    input logic [`DATA_ADDR_BUS-$clog2(`CACHE_BLOCK_SIZE)-$clog2(`NUM_CACHE_SET)-1:0]
                tag [`NUM_CACHE_WAY][`NUM_CACHE_SET],

    input logic [`DATA_WIDTH-1:0]
                cache_data [`NUM_CACHE_WAY][`NUM_CACHE_SET][`WORDS_PER_BLOCK],

    input logic [$clog2(`NUM_CACHE_WAY)-1:0]
                alloc_way [`NUM_CACHE_SET],
    input logic miss_done,
    input logic [$clog2(`NUM_CACHE_SET)-1:0] index_in,
    input logic [$clog2(`NUM_CACHE_WAY)-1:0] curr_alloc_way,
    input logic cpu_req_handshake,
    input logic hit_sign,
    input logic [$clog2(`NUM_CACHE_WAY)-1:0] hit_way,
    input logic cpu_wr_en,
   // input logic miss_done,
    input logic wb_done,
    input logic mem_req_valid,
    input logic mem_req_ready,
    input logic mem_resp_ready,
    input logic mem_resp_valid,
    input logic mem_wr_en,
    input logic [`DATA_ADDR_BUS-1:0] mem_addr,
    input logic [8*`CACHE_BLOCK_SIZE-1:0] mem_wdata,
    input logic [8*`CACHE_BLOCK_SIZE-1:0] mem_rdata,
    input logic [1:0] curr_state,
    input logic cpu_req_valid,
    input logic cpu_req_ready,
    input logic [`DATA_ADDR_BUS-1:0] cpu_req_addr,
    input logic [`DATA_WIDTH-1:0] cpu_wdata,
    input logic cpu_resp_ready,
    input logic cpu_resp_valid,
    input logic [`DATA_WIDTH-1:0] cache_rdata
);

endinterface