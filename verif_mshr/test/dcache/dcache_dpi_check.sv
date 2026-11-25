// 仅检查原C++模型/稀疏内存的DPI连接，不实例化DUT，不计为Cache功能通过。
module dcache_dpi_check;
    import dcache_params_pkg::*;
    import dcache_pkg::*;
    chandle reference_handle;
    chandle memory_handle;
    int unsigned inputs[SAMPLE_WORDS];
    int unsigned outputs[SAMPLE_WORDS];
    bit [511:0] written;
    bit [511:0] observed;
    initial begin
        reference_handle = dcache_ref_create();
        memory_handle = dcache_mem_create();
        if (reference_handle == null || memory_handle == null) $fatal(1, "DPI create failed");
        foreach (inputs[index]) inputs[index] = 0;
        // dcache_ref_step调用原CacheTop reset/eval/tick，检查开放数组ABI可正常使用。
        if (!dcache_ref_step(reference_handle, 1, inputs, outputs)) $fatal(1, "Reference reset failed");
        repeat (4) begin
            if (!dcache_ref_step(reference_handle, 0, inputs, outputs)) $fatal(1, "Reference idle step failed");
        end
        for (int word = 0; word < 16; word++) written[word*32 +: 32] = 'h12340000 + word;
        // 读写的是RefModel/MEM/SparseMemory.hpp，检查packed整行和字节顺序的DPI往返。
        if (!dcache_mem_write(memory_handle, 'h1000, written) ||
            !dcache_mem_read(memory_handle, 'h1000, observed) || observed !== written) begin
            $fatal(1, "SparseMemory line round trip failed");
        end
        dcache_ref_destroy(reference_handle);
        dcache_mem_destroy(memory_handle);
        $display("DCACHE_DPI_LINK_PASS (no DUT instantiated)");
        $finish;
    end
endmodule
