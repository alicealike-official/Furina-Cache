// 公共黑盒场景工具；只通过CPU/内存接口工作，检查目标交给scenario test统一判定。
class dcache_scenario_sequence extends dcache_base_sequence;
    typedef struct {
        string label;
        int actual;
        int expected;
        bit at_least;
    } check_record_t;
    check_record_t checks[$];
    int submitted;
    int request_origin;
    int next_id;
    int eviction_round;
    int required_hits[string];
    protected dcache_config cfg;
    protected dcache_activity_monitor obs;
    // 原C++ SparseMemory封装，与observer中的架构期望实例分离。
    protected dcache_memory_store memory;
    `uvm_object_utils(dcache_scenario_sequence)
    function new(string name = "dcache_scenario_sequence");
        super.new(name);
    endfunction
    task pre_body();
        dcache_sequencer sequencer;
        super.pre_body();
        // 【防御性检查】只在配套sequencer上运行，所有观察对象来自环境。
        if (!$cast(sequencer, get_sequencer()) || sequencer.observations == null || sequencer.memory == null) begin
            `fatal("Scenario dependencies missing", "DCACHE_CONFIG")
        end
        cfg = sequencer.cfg;
        obs = sequencer.observations;
        memory = sequencer.memory;
        request_origin = obs.requests;
    endtask
    // 按公开地址布局构造同组不同tag或不同行内字，避免使用无意义地址常量。
    function bit [31:0] address(int set_index, int tag, int word_index = 0);
        return (32'(tag) << 11) | (32'(set_index) << 6) | (32'(word_index) << 2);
    endfunction
    // 预置外部MEM及同一初始架构内容，只用于尚未访问的冷块。
    function void preload(bit [31:0] addr, bit [511:0] line);
        // 两次write_line均经dcache_mem_write DPI调用原C++ SparseMemory，二者后续独立更新。
        memory.write_line(addr, line);
        obs.architecture.write_line(addr, line);
    endfunction
    // 生成全0/1、交替位、逐字/逐字节、单1/单0遍历及随机整行。
    function bit [511:0] pattern_line(int pattern, int position);
        bit [511:0] line;
        case (pattern)
            0: line = '0;
            1: line = '1;
            2, 3: for (int index = 0; index < 512; index++) line[index] = bit'((index + pattern) % 2);
            4: for (int word = 0; word < 16; word++) line[word*32 +: 32] = 'h41000000 + position*16 + word;
            5: for (int byte_index = 0; byte_index < 64; byte_index++) line[byte_index*8 +: 8] = 8'(position + byte_index);
            6: begin
                line = '0;
                line[position % 512] = 1;
            end
            7: begin
                line = '1;
                line[position % 512] = 0;
            end
            default: begin
                // 【防御性检查】随机化失败不能继续提交默认数据。
                if (!std::randomize(line)) `fatal("Data randomization failed", "DCACHE_RANDOMIZE")
            end
        endcase
        return line;
    endfunction
    // 轮换选择已完成的CPU ID；wait_response只等本CPU请求，不强迫WBB的ack同时完成。
    task access(bit [31:0] addr, bit is_write = 0, bit [31:0] data = 0, bit wait_response = 1);
        int id;
        id = next_id;
        while (obs.pending[id]) obs.wait_cycles(1);
        next_id = (id + 1) % 32;
        submit(addr, is_write, data, 5'(id));
        submitted++;
        // 等monitor记录本笔接受再检查pending，连续模式下可能仍处于同一采样沿的回调调度中。
        while (obs.requests < request_origin + submitted) @obs.sampled;
        if (wait_response) begin
            while (obs.pending[id]) obs.wait_cycles(1);
        end
    endtask
    // 保存本阶段的观测值与要求，test统一报错；不因sequence执行到此就当作命中。
    function void record_check(string label, int actual, int expected, bit at_least = 0);
        check_record_t item;
        item.label = label;
        item.actual = actual;
        item.expected = expected;
        item.at_least = at_least;
        checks.push_back(item);
    endfunction
    // 使用四个新tag替换目标set原行；由实际写回记录确认受测脏行确实被驱逐。
    task evict_set(int set_index);
        for (int index = 0; index < 4; index++) begin
            access(address(set_index, 1024 + eviction_round*4 + index));
        end
        eviction_round++;
    endtask
    // 准备四条可区分的脏行，保持CPU外部可见的数据期望。
    task dirty_set(int set_index);
        for (int tag = 1; tag <= 4; tag++) begin
            for (int word = 0; word < 16; word++) begin
                access(address(set_index, tag, word), 1, 'ha5000000 + tag*256 + word);
            end
        end
    endtask
    // 实际写回及ack完成后，逐行比较受测地址的后端与架构最终值。
    task check_evicted_set(int set_index, int first_tag = 1, int count_lines = 4);
        bit [511:0] actual;
        bit [511:0] expected;
        int matching_writes;
        obs.wait_empty();
        for (int tag = first_tag; tag < first_tag + count_lines; tag++) begin
            matching_writes = 0;
            foreach (obs.write_samples[index]) begin
                if (obs.write_samples[index].memWriteReq_payload_addr == address(set_index, tag)) matching_writes++;
            end
            record_check("target actually written back", matching_writes, 1, 1);
            // 两个read_line通过原C++ SparseMemory DPI分别读取实际后端和CPU期望。
            memory.read_line(address(set_index, tag), actual);
            obs.architecture.read_line(address(set_index, tag), expected);
            record_check("evicted line equals latest CPU value", actual === expected, 1);
        end
    endtask
    // 放行全部外部通道并收尾；不要求未驱逐的脏Cache行已经写入后端。
    task finish_scenario();
        obs.wait_cycles(1);
        cfg.read_request_enable = 1;
        cfg.write_request_enable = 1;
        cfg.read_response_enable = 1;
        cfg.write_response_enable = 1;
        cfg.cpu_read_ready = 1;
        cfg.cpu_write_ready = 1;
        obs.wait_empty();
    endtask
endclass
