// write_allocate场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_write_allocate_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_write_allocate_sequence)
    function new(string name = "dcache_write_allocate_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_write_allocate_sequence::body();
    int before_reads;
    for (int edge_word = 0; edge_word < 2; edge_word++) begin
        preload(address(edge_word, 1), pattern_line(4, edge_word));
        before_reads = obs.reads;
        access(address(edge_word, 1, edge_word == 0 ? 0 : 15), 1, 'hdeadbeef);
        for (int word = 0; word < 16; word++) access(address(edge_word, 1, word));
        record_check("cold write reads exactly one line", obs.reads-before_reads, 1);
        evict_set(edge_word);
        check_evicted_set(edge_word, 1, 1);
    end
    finish_scenario();
endtask
