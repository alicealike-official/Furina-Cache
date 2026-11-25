// merge_history场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_merge_history_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_merge_history_sequence)
    function new(string name = "dcache_merge_history_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_merge_history_sequence::body();
    int before_reads;
    int writes_mask;
    for (int variant = 0; variant < 8; variant++) begin
        cfg.read_response_enable = 0;
        before_reads = obs.reads;
        writes_mask = variant % 4 == 0 ? 4'b1010 : variant % 4 == 1 ? 4'b0101 : variant % 4 == 2 ? 4'b0011 : 4'b1100;
        preload(address(variant, 1), pattern_line(4, variant));
        for (int slot = 0; slot < 4; slot++) begin
            access(address(variant, 1, variant < 4 ? 0 : slot % 2), bit'((writes_mask >> slot) & 1),
                'h34120000 + variant*16 + slot, 0);
        end
        obs.wait_cycles(4);
        cfg.read_response_enable = 1;
        obs.wait_empty();
        record_check("four accepted same-line requests share one read", obs.reads-before_reads, 1);
        for (int word = 0; word < 16; word++) access(address(variant, 1, word));
    end
    finish_scenario();
endtask
