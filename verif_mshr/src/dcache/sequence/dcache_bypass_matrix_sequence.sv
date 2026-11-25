// 当前FIFO配置的定向场景；只通过正常CPU/内存接口驱动，探针用于命中和结果检查。
class dcache_bypass_matrix_sequence extends dcache_probe_sequence;
    `uvm_object_utils(dcache_bypass_matrix_sequence)
    function new(string name = "dcache_bypass_matrix_sequence");
        super.new(name);
    endfunction
    // 分别改变旁路比较字段，检查只有完整同字匹配才能选用上一笔写数据。
    task body();
        bit [31:0] target;
        bit [31:0] other;
        cfg.continuous_cpu = 1;
        // 相同set不同tag会落到不同way；不同set可使用相同way，分别覆盖比较键。
        access(address(0,1));
        access(address(0,2));
        access(address(1,1));
        for (int kind = 0; kind < 4; kind++) begin
            target = address(0,1);
            case (kind)
                0: other = address(0,1,1);
                1: other = address(0,2);
                2: other = address(1,1);
                default: other = target;
            endcase
            access(target,1,'h11110000+kind,0);
            access(other,0,0,0);
            access(target,0,0,0);
            obs.wait_empty();
        end
        finish_scenario();
        required_probe_hits["bypass_used"] = 1;
        required_probe_hits["bypass_reject_tag"] = 1;
        required_probe_hits["bypass_reject_way"] = 1;
        required_probe_hits["bypass_reject_set"] = 1;
        required_probe_hits["bypass_reject_word"] = 1;
    endtask
endclass
