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
                alloc_way [`NUM_CACHE_SET]
);

endinterface