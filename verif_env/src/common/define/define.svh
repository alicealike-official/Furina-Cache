//=================仿真配置===============//
`define DEBUG




`define DATA_ADDR_BUS  32
`define DATA_WIDTH     32
// ============ Cache 参数配置（顶层统一修改）============
`define NUM_CACHE_SET        32
`define CACHE_BLOCK_SIZE     64
`define NUM_CACHE_WAY        1
`define WORDS_PER_BLOCK       (`CACHE_BLOCK_SIZE / (`DATA_WIDTH / 8))

