// 固定规格来自架构文档；生成接入脚本核对公开端口，DPI核对原C++模型参数。
package dcache_params_pkg;
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int LINE_WIDTH = 512;
    parameter int BLOCK_SIZE = 64;
    parameter int CPU_ID_WIDTH = 5;
    parameter int BUS_ID_WIDTH = 4;
    parameter int MSHR_ENTRIES = 4;
    parameter int WBB_ENTRIES = 4;
    parameter int NUM_SETS = 32;
    parameter int NUM_WAYS = 4;
    parameter int SAMPLE_WORDS = 59;
endpackage
