// 按spec §6.6验证CPU同字写后读；随机数据与顺序均由sequence生成。
class dcache_read_during_write_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_read_during_write_sequence)
    function new(string name = "dcache_read_during_write_sequence");
        super.new(name);
    endfunction

    // 预热两个set的四条行，让后续读写走命中路径，并由实际W1端口统计最终way。
    task warm_lines();
        for (int set_index = 0; set_index < 2; set_index++) begin
            for (int tag = 1; tag <= NUM_WAYS; tag++) begin
                access(address(set_index, tag));
            end
        end
    endtask

    // W-R取第一次写，W-W-R取最后一次写，W-R-W-R检查后续写不会改变前一笔读的历史值。
    task run_word_patterns(bit [ADDR_WIDTH-1:0] word_addr);
        bit [DATA_WIDTH-1:0] first_value;
        bit [DATA_WIDTH-1:0] last_value;
        // 【防御性检查】生成两个不同的值，避免旧值与新值恰好相等掩盖选择错误。
        if (!std::randomize(first_value, last_value) with { first_value != last_value; }) begin
            `fatal("Read-during-write data randomization failed", "DCACHE_RANDOMIZE")
        end

        // 单次写后立即读。
        access(word_addr, 1, first_value, 0);
        access(word_addr, 0, 0, 0);

        // 连续两次覆盖写后读，应选择第二次写的数据。
        access(word_addr, 1, first_value, 0);
        access(word_addr, 1, last_value, 0);
        access(word_addr, 0, 0, 0);

        // 两笔读分别对应不同写版本，由CPU接受顺序数据检查核对。
        access(word_addr, 1, first_value, 0);
        access(word_addr, 0, 0, 0);
        access(word_addr, 1, last_value, 0);
        access(word_addr, 0, 0, 0);
    endtask

    // 打乱每条行内的字顺序；每轮仍完整访问全部16个字，避免随机遗漏边界位置。
    task run_sweep();
        int word_order[LINE_WIDTH / DATA_WIDTH];
        for (int set_index = 0; set_index < 2; set_index++) begin
            for (int tag = 1; tag <= NUM_WAYS; tag++) begin
                foreach (word_order[index]) word_order[index] = index;
                word_order.shuffle();
                foreach (word_order[index]) begin
                    run_word_patterns(address(set_index, tag, word_order[index]));
                end
            end
        end
    endtask

    // 每个way/word都必须发生真实同沿读写；未命中的场景不能只凭最终数据正确算通过。
    function void require_collisions();
        for (int way = 0; way < NUM_WAYS; way++) begin
            for (int word_index = 0; word_index < LINE_WIDTH / DATA_WIDTH; word_index++) begin
                required_probe_hits[$sformatf("same_edge_wr_way_word_%0d_%0d", way, word_index)] = 1;
            end
        end
        required_probe_hits["same_edge_wr_observed"] = 64;
        required_probe_hits["same_edge_wr_checked"] = 64;
        required_probe_hits["same_edge_wr_after_two_writes"] = 64;
        required_probe_hits["bypass_used"] = 64;
    endfunction

    // 两轮随机写值和字顺序；原C++模型、CPU顺序期望、IP检查和SVA持续启用。
    task body();
        cfg.continuous_cpu = 1;
        warm_lines();
        repeat (2) run_sweep();
        finish_scenario();
        require_collisions();
        record_check("all raw requests completed", obs.responses, 2312);
    endtask
endclass
