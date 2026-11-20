// Generated together with Mshr.v; do not edit independently.
package mshr_params_pkg;
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int BLOCK_SIZE = 64;
    parameter int LINE_WIDTH = 512;
    parameter int WORDS_PER_BLOCK = 16;
    parameter int NUM_SETS = 32;
    parameter int NUM_WAYS = 4;
    parameter int MSHR_ENTRIES = 4;
    parameter int MSHR_MAX_PENDING = 4;
    parameter int TAG_WIDTH = 21;
    parameter int INDEX_WIDTH = 5;
    parameter int WAY_WIDTH = 2;
    parameter int WORD_OFF_WIDTH = 4;
    parameter int ENTRY_WIDTH = 2;
    parameter int SLOT_WIDTH = 2;
    parameter int CPU_ID_WIDTH = 5;
    parameter int BUS_ID_WIDTH = 4;
    parameter int WBB_ENTRIES = 4;
    parameter int WBB_SLOT_WIDTH = 2;
    parameter int LOCK_WIDTH = 128;
endpackage
