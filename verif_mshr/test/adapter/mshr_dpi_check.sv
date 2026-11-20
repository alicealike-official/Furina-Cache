// 此模块只检查SV/C++适配ABI和原有模型，不实例化MSHR DUT，也不代表IP功能覆盖已闭合。
module mshr_dpi_check;
    import mshr_params_pkg::*;
    // 导入C++入口，实现在dpi/mshr_dpi.cpp，复用MSHR.hpp和SparseMemory.hpp。
    `include "pkg/mshr_dpi.svh"

    // 下面三个句柄分别对应原有C++ MSHR及两个相互独立的SparseMemory实例。
    chandle reference;
    chandle primary_memory;
    chandle isolated_memory;
    bit [LINE_WIDTH-1:0] original_line;
    bit [LINE_WIDTH-1:0] result_line;
    int empty;
    int alloc_en;
    int unsigned alloc_tag;
    int unsigned alloc_index;
    int unsigned alloc_way;
    int alloc_is_write;
    int unsigned alloc_wdata;
    int unsigned alloc_word_off;
    int unsigned alloc_resp_id;
    int alloc_has_wb;
    int unsigned alloc_wb_slot;
    int merge_en;
    int unsigned merge_entry;
    int merge_is_write;
    int unsigned merge_wdata;
    int unsigned merge_word_off;
    int unsigned merge_resp_id;
    int unsigned q0_tag;
    int unsigned q0_index;
    int unsigned q1_tag;
    int unsigned q1_index;
    int send_ready;
    int resp_fire;
    int unsigned resp_id;
    bit [LINE_WIDTH-1:0] resp_line;
    int fill_ready;
    int replay_ready;
    int hasFree;
    int freeEntry;
    int m0_hit;
    int m0_entry;
    int m0_mergeable;
    int m0_slotFree;
    int m0_freeSlot;
    int m1_hit;
    int m1_entry;
    int m1_mergeable;
    int m1_slotFree;
    int m1_freeSlot;
    int memReadReq_valid;
    int unsigned memReadReq_payload_addr;
    int unsigned memReadReq_payload_id;
    int fill_en;
    int unsigned fill_tag;
    int unsigned fill_index;
    int unsigned fill_way;
    int fill_dirty;
    bit [LINE_WIDTH-1:0] fill_line;
    int replay_valid;
    int replay_payload_isWrite;
    int unsigned replay_payload_id;
    int unsigned replay_payload_rData;

    // 检查适配调用或期望值，失败时给出当前步骤以及最近的C++错误文本。
    task check(input bit success, input string operation);
        if (!success) begin
            $fatal(1, "MSHR DPI adapter check failed (%s): %s", operation, mshr_dpi_last_error());
        end
    endtask

    // 把当前模块变量作为一次沿前快照传给DPI，返回预测并推进原C++ MSHR一拍。
    function int step_model();
        return mshr_ref_step(reference,
            alloc_en, alloc_tag, alloc_index, alloc_way,
            alloc_is_write, alloc_wdata, alloc_word_off, alloc_resp_id,
            alloc_has_wb, alloc_wb_slot, merge_en, merge_entry,
            merge_is_write, merge_wdata, merge_word_off, merge_resp_id,
            q0_tag, q0_index, q1_tag, q1_index,
            send_ready, resp_fire, resp_id, resp_line,
            fill_ready, replay_ready, hasFree, freeEntry,
            m0_hit, m0_entry, m0_mergeable, m0_slotFree,
            m0_freeSlot, m1_hit, m1_entry, m1_mergeable,
            m1_slotFree, m1_freeSlot, memReadReq_valid, memReadReq_payload_addr,
            memReadReq_payload_id, fill_en, fill_tag, fill_index,
            fill_way, fill_dirty, fill_line, replay_valid,
            replay_payload_isWrite, replay_payload_id, replay_payload_rData);
    endfunction

    initial begin
        alloc_en = '0;
        alloc_tag = '0;
        alloc_index = '0;
        alloc_way = '0;
        alloc_is_write = '0;
        alloc_wdata = '0;
        alloc_word_off = '0;
        alloc_resp_id = '0;
        alloc_has_wb = '0;
        alloc_wb_slot = '0;
        merge_en = '0;
        merge_entry = '0;
        merge_is_write = '0;
        merge_wdata = '0;
        merge_word_off = '0;
        merge_resp_id = '0;
        q0_tag = '0;
        q0_index = '0;
        q1_tag = '0;
        q1_index = '0;
        send_ready = '0;
        resp_fire = '0;
        resp_id = '0;
        resp_line = '0;
        fill_ready = '0;
        replay_ready = '0;

        if (MSHR_MAX_PENDING < 3 || NUM_SETS < 2 || WORDS_PER_BLOCK < 2) begin
            $fatal(1, "This adapter self-check requires at least three slots, two sets and two words");
        end
        // C++构造先拒绝不一致参数，失败时handle仍为空，再创建当前配置实例。
        check(!mshr_ref_create(ADDR_WIDTH, DATA_WIDTH + 1, BLOCK_SIZE, MSHR_ENTRIES,
            MSHR_MAX_PENDING, NUM_SETS, NUM_WAYS, TAG_WIDTH, INDEX_WIDTH, WAY_WIDTH,
            WORD_OFF_WIDTH, ENTRY_WIDTH, SLOT_WIDTH, CPU_ID_WIDTH, BUS_ID_WIDTH,
            WBB_ENTRIES, WBB_SLOT_WIDTH, reference), "reject mismatched configuration");
        check(reference == null, "failed creation leaves null handle");
        check(mshr_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, MSHR_ENTRIES,
            MSHR_MAX_PENDING, NUM_SETS, NUM_WAYS, TAG_WIDTH, INDEX_WIDTH, WAY_WIDTH,
            WORD_OFF_WIDTH, ENTRY_WIDTH, SLOT_WIDTH, CPU_ID_WIDTH, BUS_ID_WIDTH,
            WBB_ENTRIES, WBB_SLOT_WIDTH, reference), "create model");
        check(mshr_ref_empty(reference, empty), "query new model");
        check(empty, "new model is empty");

        // 通过DPI分别建立小页面和常规页面的C++稀疏内存，检查整行跨页及实例隔离。
        check(mshr_mem_create(16, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, primary_memory), "create small-page memory");
        check(mshr_mem_create(4096, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, isolated_memory), "create second memory");
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            original_line[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('h12340000 + word_index);
        end
        check(mshr_mem_write_line(primary_memory, BLOCK_SIZE, original_line), "preload packed memory line");
        check(mshr_mem_read_line(primary_memory, BLOCK_SIZE, result_line), "read packed memory line");
        check(result_line === original_line, "packed word order and line width");
        check(mshr_mem_read_line(isolated_memory, BLOCK_SIZE, result_line), "read independent memory");
        check(result_line === '0, "memory instance isolation");

        // R-W-R三笔Slot：最终fill取写值，但第一笔读仍取内存原值。
        alloc_en = 1;
        alloc_tag = 1;
        alloc_index = 1;
        alloc_way = 0;
        alloc_word_off = 1;
        alloc_resp_id = 1;
        q0_tag = 1;
        q0_index = 1;
        q1_tag = 2;
        q1_index = 1;
        check(step_model(), "allocate read slot");
        check(hasFree && freeEntry == 0 && !m0_hit && !memReadReq_valid, "allocation returns pre-edge outputs");

        alloc_en = 0;
        merge_en = 1;
        merge_entry = 0;
        merge_is_write = 1;
        merge_wdata = 'h89abcdef;
        merge_word_off = 1;
        merge_resp_id = 2;
        check(step_model(), "merge write slot");
        check(m0_hit && m0_entry == 0 && m0_mergeable && m0_freeSlot == 1 &&
            !m1_hit && memReadReq_valid, "query and held send prediction");
        merge_is_write = 0;
        merge_resp_id = 3;
        check(step_model(), "merge later read slot");
        check(m0_freeSlot == 2 && memReadReq_valid, "slot append order");

        merge_en = 0;
        send_ready = 1;
        check(step_model(), "accept memory read request");
        check(memReadReq_valid && memReadReq_payload_id == 0 &&
            memReadReq_payload_addr == ((1 << (INDEX_WIDTH + $clog2(BLOCK_SIZE))) | BLOCK_SIZE),
            "block address and canonical entry ID");
        send_ready = 0;
        resp_fire = 1;
        resp_id = MSHR_ENTRIES;
        resp_line = original_line;
        check(!step_model(), "reject noncanonical high response ID before index truncation");
        resp_id = 0;
        check(step_model(), "accept memory response");
        check(!fill_en && !replay_valid, "response has no same-edge fill or replay");

        resp_fire = 0;
        fill_ready = 0;
        check(step_model(), "hold pending fill");
        result_line = original_line;
        result_line[DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('h89abcdef);
        check(fill_en && fill_dirty && fill_tag == 1 && fill_index == 1 && fill_way == 0 &&
            fill_line === result_line && !m0_mergeable && !replay_valid, "merged fill and no early replay");
        fill_ready = 1;
        check(step_model(), "accept fill");
        check(fill_en && !replay_valid, "fill then replay edge separation");

        replay_ready = 1;
        check(step_model(), "first read replay");
        check(!fill_en && replay_valid && !replay_payload_isWrite && replay_payload_id == 1 &&
            replay_payload_rData == original_line[DATA_WIDTH +: DATA_WIDTH], "read before write sees original data");
        check(step_model(), "write replay");
        check(replay_valid && replay_payload_isWrite && replay_payload_id == 2, "write only returns acknowledgement");
        check(step_model(), "later read replay");
        check(replay_valid && !replay_payload_isWrite && replay_payload_id == 3 &&
            replay_payload_rData == 'h89abcdef, "later read sees preceding write after its acknowledgement");
        check(mshr_ref_empty(reference, empty), "query released model");
        check(empty, "all slots and entry released");
        resp_fire = 1;
        check(!step_model(), "reject duplicate response after release");
        resp_fire = 0;

        // 复位模型、清内存和销毁均调用原有C++对象的方法；不会触及任何DUT状态。
        check(mshr_ref_reset(reference), "reset empty reference");
        check(mshr_mem_reset(primary_memory), "reset sparse memory");
        check(mshr_mem_read_line(primary_memory, BLOCK_SIZE, result_line), "read reset memory");
        check(result_line === '0, "memory reset discards stored pages");
        check(mshr_mem_destroy(primary_memory), "destroy memory A");
        check(mshr_mem_destroy(isolated_memory), "destroy memory B");
        check(mshr_ref_destroy(reference), "destroy model");
        check(!mshr_ref_empty(reference, empty), "reject destroyed model handle");
        $display("MSHR_DPI_ADAPTER_PASS: packed memory, query, held send, fill/replay timing, read versions and lifecycle");
        $finish;
    end
endmodule
