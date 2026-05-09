//=================二选一===============//
//`define D_CACHE_TEST    //Dcache测试
`define I_CACHE_TEST    //Icache测试
//=================二选一===============//


//=================仿真配置===============//
`define DEBUG





`define DATA_ADDR_BUS  32
`define DATA_WIDTH     32
// ============ Cache 参数配置（顶层统一修改）============
`define NUM_CACHE_SET        32
`define CACHE_BLOCK_SIZE     64
`define NUM_CACHE_WAY        4
`define WORDS_PER_BLOCK       (`CACHE_BLOCK_SIZE / (`DATA_WIDTH / 8))

