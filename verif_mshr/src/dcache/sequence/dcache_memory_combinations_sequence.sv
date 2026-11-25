// 正常CPU流量随机改变地址、数据和内存时序，并要求真实端口组合命中。
class dcache_memory_combinations_sequence extends dcache_probe_sequence;
    int random_requests = 32768;
    `uvm_object_utils(dcache_memory_combinations_sequence)
    function new(string name = "dcache_memory_combinations_sequence");
        super.new(name);
    endfunction

    // 每轮填充四条行，随机选择写字次序与数据，再驱逐；四个way的16个字均要经历W2→W1→读。
    task write_read_and_evict(int round_index);
        int word_order[16];
        int set_order[8];
        bit [31:0] write_data;
        for (int index = 0; index < 8; index++) set_order[index] = index;
        set_order.shuffle();
        foreach (set_order[index]) begin
            for (int tag = 1 + round_index*16; tag <= 4 + round_index*16; tag++) begin
                access(address(set_order[index], tag));
                for (int word_index = 0; word_index < 16; word_index++) word_order[word_index] = word_index;
                word_order.shuffle();
                foreach (word_order[position]) begin
                    // 【防御性检查】随机数据必须成功生成，不能以默认值代替失败的激励。
                    if (!std::randomize(write_data)) `fatal("Data randomization failed", "DCACHE_RANDOMIZE")
                    access(address(set_order[index], tag, word_order[position]), 1, write_data);
                    access(address(set_order[index], tag, word_order[position]));
                end
            end
            evict_set(set_order[index]);
            check_evicted_set(set_order[index], 1 + round_index*16);
        end
    endtask

    // 缩小工作集并提高写比例，同时保留多于四路的tag，增加命中写与后台fill、脏淘汰并发机会。
    task random_port_overlap();
        int set_index;
        int tag;
        int word_index;
        bit is_write;
        bit [31:0] write_data;
        cfg.continuous_cpu = 1;
        cfg.random_memory_ready = 1;
        cfg.random_memory_latency = 1;
        cfg.response_order = 2;
        for (int index = 0; index < random_requests; index++) begin
            // 【防御性检查】地址范围固定为合法字对齐请求，失败时停止而不提交残留字段。
            if (!std::randomize(set_index, tag, word_index, is_write, write_data) with {
                set_index inside {[0:7]}; tag inside {[1:6]}; word_index inside {[0:15]};
                is_write dist {1 := 3, 0 := 1};
            }) `fatal("Port combination randomization failed", "DCACHE_RANDOMIZE")
            access(address(set_index, tag, word_index), is_write, write_data, 0);
            if (index % 256 == 255) obs.wait_empty();
        end
    endtask

    // 明确有限组合矩阵：双读R2路×R1字、双写有序路对及写bank、同/异组，以及每路每字的更新后读取。
    function void require_combinations();
        for (int way = 0; way < 4; way++) begin
            for (int word_index = 0; word_index < 16; word_index++) begin
                required_probe_hits[$sformatf("dual_read_way_word_%0d_%0d", way, word_index)] = 1;
                required_probe_hits[$sformatf("dual_write_bank_%0d_%0d", way, word_index)] = 1;
                required_probe_hits[$sformatf("w2_w1_r1_%0d_%0d", way, word_index)] = 1;
                required_probe_hits[$sformatf("w2_w1_r2_%0d_%0d", way, word_index)] = 1;
            end
            for (int fill_way = 0; fill_way < 4; fill_way++) begin
                required_probe_hits[$sformatf("dual_write_ways_%0d_%0d", way, fill_way)] = 1;
            end
        end
        required_probe_hits["dual_read_same_set"] = 1;
        required_probe_hits["dual_read_other_set"] = 1;
        required_probe_hits["dual_write_same_set"] = 1;
        required_probe_hits["dual_write_other_set"] = 1;
    endfunction

    // 数据激励与随机调度放在sequence；test复用公共通过判定，无命中时不能算PASS。
    task body();
        for (int round_index = 0; round_index < 2; round_index++) write_read_and_evict(round_index);
        random_port_overlap();
        finish_scenario();
        require_combinations();
    endtask
endclass
