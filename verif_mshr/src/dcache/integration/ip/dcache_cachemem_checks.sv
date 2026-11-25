// 被动CacheMem端口检查，复用原C++ CacheMem，不重写RAM或Cache模型。
class dcache_cachemem_checks extends uvm_component;
    virtual dcache_probe_interface vif;
    chandle handle;
    int unsigned inputs[36];
    int unsigned outputs[173];
    logic [20:0] tags[4];
    logic valids[4];
    logic dirty[4];
    logic [31:0] words[4];
    bit [511:0] expected_line;
    int r1_compares;
    int r2_compares;
    `uvm_component_utils(dcache_cachemem_checks)
    function new(string name = "dcache_cachemem_checks", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // 【防御性检查】真实端口探针必须存在。
        if (!uvm_config_db #(virtual dcache_probe_interface)::get(this, "", "dcache_probe_vif", vif)) begin
            `fatal("CacheMem observation missing", "DCACHE_CACHEMEM_CONFIG")
        end
        // dcache_memref_create经DPI创建RefModel/Cache/CacheMem.hpp的独立实例。
        handle = dcache_memref_create();
        // 【防御性检查】原C++模型创建失败时不能继续运行。
        if (handle == null) `fatal(dcache_last_error(), "DCACHE_CACHEMEM_DPI")
    endfunction
    task run_phase(uvm_phase phase);
        forever begin
            @(vif.mon_cb);
            compare_and_advance();
        end
    endtask
    // 读取沿前值，比较前一拍读请求的返回，再以当前真实端口推进原C++模型一次。
    function void compare_and_advance();
        capture_inputs();
        // dcache_memref_step由dpi/dcache_dpi.cpp转调原CacheMem::tick，返回沿前输出。
        if (!dcache_memref_step(handle, !vif.mon_cb.rst_n, inputs, outputs)) begin
            `fatal(dcache_last_error(), "DCACHE_CACHEMEM_DPI")
        end
        if (!vif.mon_cb.rst_n) return;
        capture_r1_outputs();
        check_metadata();
        check_r1();
        check_r2_and_inspect();
    endfunction

    // 将CacheMem真实请求端口打包给C++ DPI，含R1/R2、W1/W2、CLR与inspect。
    function void capture_inputs();
        inputs[0] = vif.mon_cb.cache_r1_en;
        inputs[1] = vif.mon_cb.cache_r1_index;
        inputs[2] = vif.mon_cb.cache_r1_wordOff;
        inputs[3] = vif.mon_cb.cache_r2_en;
        inputs[4] = vif.mon_cb.cache_r2_index;
        inputs[5] = vif.mon_cb.cache_r2_way;
        inputs[6] = vif.mon_cb.cache_w1_en;
        inputs[7] = vif.mon_cb.cache_w1_index;
        inputs[8] = vif.mon_cb.cache_w1_way;
        inputs[9] = vif.mon_cb.cache_w1_wordOff;
        inputs[10] = vif.mon_cb.cache_w1_data;
        inputs[11] = vif.mon_cb.cache_w2_en;
        inputs[12] = vif.mon_cb.cache_w2_index;
        inputs[13] = vif.mon_cb.cache_w2_way;
        inputs[14] = vif.mon_cb.cache_w2_tag;
        inputs[15] = vif.mon_cb.cache_w2_dirty;
        for (int word = 0; word < 16; word++) inputs[16+word] = vif.mon_cb.cache_w2_line[word*32 +: 32];
        inputs[32] = vif.mon_cb.cache_clr_en;
        inputs[33] = vif.mon_cb.cache_clr_index;
        inputs[34] = vif.mon_cb.cache_clr_way;
        inputs[35] = vif.mon_cb.cache_inspect_index;
    endfunction

    // 将展平的四路R1返回整理为数组，供统一的逐路检查使用。
    function void capture_r1_outputs();
        tags[0] = vif.mon_cb.cache_r1_tag_0;
        valids[0] = vif.mon_cb.cache_r1_valid_0;
        dirty[0] = vif.mon_cb.cache_r1_dirty_0;
        words[0] = vif.mon_cb.cache_r1_data_0;
        tags[1] = vif.mon_cb.cache_r1_tag_1;
        valids[1] = vif.mon_cb.cache_r1_valid_1;
        dirty[1] = vif.mon_cb.cache_r1_dirty_1;
        words[1] = vif.mon_cb.cache_r1_data_1;
        tags[2] = vif.mon_cb.cache_r1_tag_2;
        valids[2] = vif.mon_cb.cache_r1_valid_2;
        dirty[2] = vif.mon_cb.cache_r1_dirty_2;
        words[2] = vif.mon_cb.cache_r1_data_2;
        tags[3] = vif.mon_cb.cache_r1_tag_3;
        valids[3] = vif.mon_cb.cache_r1_valid_3;
        dirty[3] = vif.mon_cb.cache_r1_dirty_3;
        words[3] = vif.mon_cb.cache_r1_data_3;
    endfunction

    // 所有组的元数据按真实写入/清valid历史核对，未初始化且无效的tag不比较。
    function void check_metadata();
        for (int location = 0; location < 128; location++) begin
            if (vif.mon_cb.cache_valid_map[location] !== outputs[37+location/32][location%32] ||
                vif.mon_cb.cache_dirty_map[location] !== outputs[41+location/32][location%32] ||
                (outputs[37+location/32][location%32] &&
                vif.mon_cb.cache_tag_map[location*21 +: 21] !== 21'(outputs[45+location]))) begin
                `error($sformatf("Cache metadata location=%0d differs from write/clear history", location), "DCACHE_CACHEMEM_METADATA")
            end
        end
    endfunction

    // 仅比较有效读请求及无同址写碰撞的路；未初始化无效行的数据不作要求。
    function void check_r1();
        for (int way = 0; way < 4; way++) begin
            if (outputs[34][way]) begin
                r1_compares++;
                if (valids[way] !== 1'(outputs[way*4+1]) || dirty[way] !== 1'(outputs[way*4+2]) ||
                    (outputs[35][way] && (tags[way] !== 21'(outputs[way*4]) || words[way] !== outputs[way*4+3]))) begin
                    `error($sformatf("R1 way=%0d differs from previous accepted read", way), "DCACHE_CACHEMEM_R1")
                end
            end
        end
    endfunction

    // 核对上一拍R2整行返回及当前inspect；同拍同址读写的原语返回新旧值不作要求。
    function void check_r2_and_inspect();
        if (outputs[36]) begin
            for (int word = 0; word < 16; word++) expected_line[word*32 +: 32] = outputs[16+word];
            if (vif.mon_cb.cache_r2_line !== expected_line) begin
                `error("R2 line differs from previous read request", "DCACHE_CACHEMEM_R2")
            end
            r2_compares++;
        end
        if (vif.mon_cb.cache_inspect_valid !== 4'(outputs[32]) || vif.mon_cb.cache_inspect_dirty !== 4'(outputs[33])) begin
            `error("inspect differs from current accepted write/clear history", "DCACHE_CACHEMEM_INSPECT")
        end
    endfunction
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `info($sformatf("r1_checked=%0d r2_checked=%0d same-cycle collisions excluded pending RAM contract",
            r1_compares, r2_compares), "DCACHE_CACHEMEM_COVERAGE")
    endfunction
    function void final_phase(uvm_phase phase);
        super.final_phase(phase);
        // dcache_memref_destroy经DPI释放原C++ CacheMem独立实例。
        dcache_memref_destroy(handle);
    endfunction
endclass
