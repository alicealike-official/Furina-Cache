// Infrastructure-only ABI check. No DUT or WBB functional sequence is instantiated.
module dpi_adapter_check;
    import wbb_params_pkg::*;
    `include "pkg/wbb_dpi.svh"
    chandle actual_mem;
    chandle expected_mem;
    chandle reference;
    bit [LINE_WIDTH-1:0] line;
    bit [LINE_WIDTH-1:0] result;
    int reserve_ok, reserve_slot, full, q0_same, q1_same, send_valid;
    int unsigned send_addr, send_id;
    int empty;

    // 检查传入的成功标志，失败时通过 $fatal 终止适配自检并附带最近的 DPI 错误信息。
    // 若失败的是数据比较等 SV 条件，最近的 DPI 错误字符串可能为空。
    task check(input bit success);
        if (!success) begin
            $fatal(1, "DPI adapter check failed: %s", wbb_dpi_last_error());
        end
    endtask

    initial begin
        check(!wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE,
            WBB_ENTRIES + 1, SLOT_WIDTH, BUS_ID_WIDTH, reference));
        check(reference == null);
        check(wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE,
            WBB_ENTRIES, SLOT_WIDTH, BUS_ID_WIDTH, reference));
        check(sparse_mem_create(16, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, actual_mem));
        check(sparse_mem_create(4096, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, expected_mem));
        for (int w = 0; w < WORDS_PER_BLOCK; w++) begin
            line[w * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('h89abcdef ^ w);
        end
        check(sparse_mem_write_line(actual_mem, 'h1000, line));
        check(sparse_mem_read_line(actual_mem, 'h1000, result));
        check(result === line);
        check(sparse_mem_read_line(expected_mem, 'h1000, result));
        check(result === '0);
        check(wbb_ref_step(reference, 1, 'h1000, 0, 0, line, 0, 0, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(reserve_ok == 1 && reserve_slot == 0 && q0_same == 0 && send_valid == 0);
        check(wbb_ref_step(reference, 0, 0, 1, 0, line, 0, 0, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(q0_same == 1 && q1_same == 0 && send_valid == 0);
        check(wbb_ref_step(reference, 0, 0, 0, 0, line, 1, 0, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(send_valid == 1 && send_addr == 'h1000 && send_id == 0 && result === line);
        check(sparse_mem_write_line(expected_mem, send_addr, result));
        check(sparse_mem_read_line(expected_mem, 'h1000, result));
        check(result === line);
        check(wbb_ref_step(reference, 0, 0, 0, 0, line, 0, 1, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(wbb_ref_empty(reference, empty));
        check(empty == 1);
        check(sparse_mem_reset(actual_mem));
        check(sparse_mem_read_line(actual_mem, 'h1000, result));
        check(result === '0);
        check(sparse_mem_destroy(actual_mem));
        check(sparse_mem_destroy(expected_mem));
        check(wbb_ref_destroy(reference));
        $display("DPI_ADAPTER_PASS: packed line, model step, isolation and lifetime checked");
        $finish;
    end
endmodule
