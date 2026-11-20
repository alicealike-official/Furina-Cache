// Infrastructure-only ABI check. No DUT or WBB functional sequence is instantiated.
module dpi_adapter_check;
    import wbb_params_pkg::*;
    // 本模块直接导入 C++ DPI 声明；下面的 wbb_ref_* / sparse_mem_* 实现在 dpi/wbb_dpi.cpp。
    // 对应模型分别为 RefModel/Cache/WriteBackBuffer.hpp 和 RefModel/MEM/SparseMemory.hpp。
    `include "pkg/wbb_dpi.svh"
    // DPI 创建的 C++ SparseMemory 实际内存句柄，模型定义见 RefModel/MEM/SparseMemory.hpp。
    chandle actual_mem;
    // 第二个独立 C++ SparseMemory 实例句柄，用于期望数据及实例隔离检查。
    chandle expected_mem;
    // DPI 创建的 C++ WBB 模型句柄，模型定义见 RefModel/Cache/WriteBackBuffer.hpp。
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
            // wbb_dpi_last_error() 同样是 DPI 接口，读取 C++ 适配层保存的最近错误文本。
            $fatal(1, "DPI adapter check failed: %s", wbb_dpi_last_error());
        end
    endtask

    initial begin
        // 直接调用 C++ WBB 创建接口，先验证错误配置被拒绝，再创建有效实例。
        check(!wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE,
            WBB_ENTRIES + 1, SLOT_WIDTH, BUS_ID_WIDTH, reference));
        check(reference == null);
        check(wbb_ref_create(ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE,
            WBB_ENTRIES, SLOT_WIDTH, BUS_ID_WIDTH, reference));

        // 经 DPI 创建两份独立的 C++ SparseMemory，后续分别写入和回读以检查隔离。
        check(sparse_mem_create(16, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, actual_mem));
        check(sparse_mem_create(4096, ADDR_WIDTH, DATA_WIDTH, BLOCK_SIZE, expected_mem));
        for (int word_index = 0; word_index < WORDS_PER_BLOCK; word_index++) begin
            line[word_index * DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'('h89abcdef ^ word_index);
        end
        // 下面的稀疏内存 DPI 读写最终进入 SparseMemory::writeLine()/readLine()。
        check(sparse_mem_write_line(actual_mem, 'h1000, line));
        check(sparse_mem_read_line(actual_mem, 'h1000, result));
        check(result === line);
        check(sparse_mem_read_line(expected_mem, 'h1000, result));
        check(result === '0);

        // 预留首行：沿前仍为空态；DPI比较输出后才推进C++模型建立占用。
        check(wbb_ref_step(reference, 1, 'h1000, 0, 0, line, 0, 0, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(reserve_ok == 1 && reserve_slot == 0 && q0_same == 0 && send_valid == 0);

        // 装载预留行：沿前查询已经命中，但尚不能发送未push的数据。
        check(wbb_ref_step(reference, 0, 0, 1, 0, line, 0, 0, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(q0_same == 1 && q1_same == 0 && send_valid == 0);

        // 接受首次发送：核对C++模型返回的地址、ID和完整行。
        check(wbb_ref_step(reference, 0, 0, 0, 0, line, 1, 0, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));
        check(send_valid == 1 && send_addr == 'h1000 && send_id == 0 && result === line);

        // 把 C++ WBB 返回的数据经 DPI 写入期望 SparseMemory，再回读核对。
        check(sparse_mem_write_line(expected_mem, send_addr, result));
        check(sparse_mem_read_line(expected_mem, 'h1000, result));
        check(result === line);

        // 接受对应写响应：释放已发送槽，随后检查模型排空。
        check(wbb_ref_step(reference, 0, 0, 0, 0, line, 0, 1, 0,
            'h1000, 'h2000, reserve_ok, reserve_slot, full, q0_same, q1_same,
            send_valid, send_addr, result, send_id));

        // DPI 查询 C++ WBB 是否排空，实际结果由 empty 输出。
        check(wbb_ref_empty(reference, empty));
        check(empty == 1);

        // DPI 清空实际 C++ 内存，再回读验证 reset() 的存储语义。
        check(sparse_mem_reset(actual_mem));
        check(sparse_mem_read_line(actual_mem, 'h1000, result));
        check(result === '0);

        // 经 DPI 释放前面创建的两个 C++ 内存实例和一个 WBB 实例。
        check(sparse_mem_destroy(actual_mem));
        check(sparse_mem_destroy(expected_mem));
        check(wbb_ref_destroy(reference));
        $display("DPI_ADAPTER_PASS: packed line, model step, isolation and lifetime checked");
        $finish;
    end
endmodule
