// data_pattern场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_data_pattern_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_data_pattern_sequence)
    function new(string name = "dcache_data_pattern_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_data_pattern_sequence::body();
    int line_index;
    int iterations;
    bit [31:0] addr;
    line_index = 0;
    for (int pattern = 0; pattern < 9; pattern++) begin
        iterations = pattern inside {6,7} ? 512 : 16;
        for (int position = 0; position < iterations; position++) begin
            addr = address(line_index % 32, 1 + line_index/32);
            preload(addr, pattern_line(pattern, position));
            for (int word = 0; word < 16; word++) access(addr + word*4);
            access(addr, 1, ~32'(position));
            access(addr);
            line_index++;
        end
    end
    finish_scenario();
    record_check("pattern lines exercised", line_index, 1136);
endtask
