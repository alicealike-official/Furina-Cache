// hit_access场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_hit_access_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_hit_access_sequence)
    function new(string name = "dcache_hit_access_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_hit_access_sequence::body();
    int before_reads;
    // 每个set填四个tag，逐字写读后重新扫读，确认预热阶段之后没有新增内存读。
    for (int set_index = 0; set_index < 32; set_index++) begin
        for (int tag = 1; tag <= 4; tag++) access(address(set_index, tag));
        before_reads = obs.reads;
        for (int tag = 1; tag <= 4; tag++) begin
            for (int word = 0; word < 16; word++) begin
                access(address(set_index, tag, word), 1, 'h12340000 + set_index*1024 + tag*16 + word);
                access(address(set_index, tag, word));
            end
        end
        record_check("warm accesses issue no new memory read", obs.reads - before_reads, 0);
    end
    finish_scenario();
endtask
