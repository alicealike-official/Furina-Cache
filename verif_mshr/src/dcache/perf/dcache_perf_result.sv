// 只保存测量结果，不预测Cache行为；所有周期来自真实IO与既有只读接口。
class dcache_perf_result extends uvm_object;
    string scenario;
    string submission;
    int expected_requests;
    int group_size;
    int configured_read_latency;
    int configured_write_latency;
    bit started;
    longint first_present, first_accept, last_accept, last_response, last_completion;
    int requests, responses, read_requests, write_requests;
    int mem_reads, mem_writes, mem_read_acks, mem_write_acks;
    int hit_count, alloc_count, merge_count, reserve_count;
    int input_stalls, input_idle, stalls_to_last_accept, idle_to_last_accept;
    int mem_read_stalls, mem_write_stalls, read_stalls_at_completion, write_stalls_at_completion;
    int mshr_full_stalls, wbb_full_stalls, same_line_stalls;
    int mshr_full_at_last_accept, wbb_full_at_last_accept, same_line_at_last_accept;
    int cpu_outstanding, max_cpu_outstanding;
    int peak_mshr, peak_wbb;
    longint mshr_sum, wbb_sum, mshr_sum_at_completion, wbb_sum_at_completion;
    int read_latencies[$], write_latencies[$];
    int memory_read_latencies[$], memory_write_latencies[$];
    `uvm_object_utils(dcache_perf_result)

    function new(string name = "dcache_perf_result");
        super.new(name);
    endfunction

    // 测量窗口按有效采样拍计数，两端均包含；延迟则用两个握手沿编号直接相减。
    function longint cpu_cycles();
        return last_response - first_present + 1;
    endfunction

    // 包括末尾已发内存写的确认，排除为了检查空闲而额外等待的拍数。
    function longint settled_cycles();
        return last_completion - first_present + 1;
    endfunction

    // 首次呈现到最后接受的窗口用于区分DUT反压和TB没有提供请求。
    function longint presentation_cycles();
        return last_accept - first_present + 1;
    endfunction

    // 连续命中时应为N拍接受N笔；不会把末尾响应排空开销混入这个指标。
    function longint acceptance_cycles();
        return last_accept - first_accept + 1;
    endfunction

    // 对已有真实样本求均值；空集合由JSON导出为null，不能当作零延迟。
    function real mean_latency(ref int values[$]);
        longint total;
        total = 0;
        foreach (values[index]) total += values[index];
        return values.size() == 0 ? 0.0 : real'(total) / values.size();
    endfunction

    // 使用nearest-rank分位数；排序只在测量结束后进行，不改变运行中的采样顺序。
    function int percentile(ref int values[$], input int percent);
        int rank;
        if (values.size() == 0) return 0;
        values.sort();
        rank = (percent * values.size() + 99) / 100;
        return values[rank-1];
    endfunction

    // 输出一组周期延迟，读、写和两个内存方向分开统计。
    function void write_distribution(input int file_handle, input string field,
        ref int values[$], input bit comma = 1);
        $fwrite(file_handle, "  \"%s\": {\"samples\": %0d, ", field, values.size());
        if (values.size() == 0) begin
            $fwrite(file_handle, "\"mean\": null, \"p50\": null, \"p95\": null, \"max\": null}");
        end else begin
            $fwrite(file_handle, "\"mean\": %0.6f, \"p50\": %0d, \"p95\": %0d, \"max\": %0d}",
                mean_latency(values), percentile(values, 50), percentile(values, 95), percentile(values, 100));
        end
        $fwrite(file_handle, "%s", comma ? ",\n" : "\n");
    endfunction

    // 写出可重建报告的原始周期计数；没有把仿真时钟频率当作硅后频率。
    function void write_json(string path);
        int file_handle;
        file_handle = $fopen(path, "w");
        // 【防御性检查】不能把缺少结果文件的运行登记成性能测试成功。
        if (file_handle == 0) begin
            `fatal($sformatf("Cannot open performance result: %s", path), "DCACHE_PERF_FILE")
        end
        $fwrite(file_handle, "{\n  \"scenario\": \"%s\", \"submission\": \"%s\",\n", scenario, submission);
        $fwrite(file_handle, "  \"group_size\": %0d, \"read_latency_cycles\": %0d, \"write_latency_cycles\": %0d,\n",
            group_size, configured_read_latency, configured_write_latency);
        $fwrite(file_handle, "  \"requests\": %0d, \"responses\": %0d, \"cpu_reads\": %0d, \"cpu_writes\": %0d,\n",
            requests, responses, read_requests, write_requests);
        $fwrite(file_handle, "  \"cpu_cycles\": %0d, \"settled_cycles\": %0d, \"presentation_cycles\": %0d, \"acceptance_cycles\": %0d,\n",
            cpu_cycles(), settled_cycles(), presentation_cycles(), acceptance_cycles());
        $fwrite(file_handle, "  \"completion_throughput\": %0.8f, \"acceptance_throughput\": %0.8f,\n",
            real'(responses)/cpu_cycles(), real'(requests)/acceptance_cycles());
        $fwrite(file_handle, "  \"cpu_stall_cycles\": %0d, \"source_idle_cycles\": %0d,\n", stalls_to_last_accept, idle_to_last_accept);
        $fwrite(file_handle, "  \"cpu_stall_mshr_full\": %0d, \"cpu_stall_wbb_full\": %0d, \"cpu_stall_same_line\": %0d,\n",
            mshr_full_at_last_accept, wbb_full_at_last_accept, same_line_at_last_accept);
        $fwrite(file_handle, "  \"memory_read_requests\": %0d, \"memory_read_acks\": %0d, \"memory_write_requests\": %0d, \"memory_write_acks\": %0d,\n",
            mem_reads, mem_read_acks, mem_writes, mem_write_acks);
        $fwrite(file_handle, "  \"memory_read_stall_cycles\": %0d, \"memory_write_stall_cycles\": %0d,\n",
            read_stalls_at_completion, write_stalls_at_completion);
        $fwrite(file_handle, "  \"hit_count\": %0d, \"alloc_count\": %0d, \"merge_count\": %0d, \"reserve_count\": %0d,\n",
            hit_count, alloc_count, merge_count, reserve_count);
        $fwrite(file_handle, "  \"peak_cpu_outstanding\": %0d, \"peak_mshr\": %0d, \"peak_wbb\": %0d,\n",
            max_cpu_outstanding, peak_mshr, peak_wbb);
        $fwrite(file_handle, "  \"mean_mshr\": %0.6f, \"mean_wbb\": %0.6f,\n",
            real'(mshr_sum_at_completion)/settled_cycles(), real'(wbb_sum_at_completion)/settled_cycles());
        write_distribution(file_handle, "read_latency", read_latencies);
        write_distribution(file_handle, "write_latency", write_latencies);
        write_distribution(file_handle, "memory_read_latency", memory_read_latencies);
        write_distribution(file_handle, "memory_write_latency", memory_write_latencies, 0);
        $fwrite(file_handle, "}\n");
        $fclose(file_handle);
    endfunction
endclass
