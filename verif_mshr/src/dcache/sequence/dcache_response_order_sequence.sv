// response_order场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_response_order_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_response_order_sequence)
    function new(string name = "dcache_response_order_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_response_order_sequence::body();
    cfg.read_response_enable = 0;
    for (int index = 0; index < 4; index++) access(address(index, 1), 0, 0, 0);
    obs.wait_cycles(16);
    cfg.response_order = 1;
    cfg.read_response_enable = 1;
    obs.wait_empty();
    dirty_set(8);
    cfg.write_response_enable = 0;
    for (int tag = 5; tag <= 8; tag++) access(address(8, tag));
    obs.wait_cycles(16);
    cfg.write_response_enable = 1;
    finish_scenario();
    required_hits["read_reorder"] = 3;
    required_hits["write_reorder"] = 3;
endtask
