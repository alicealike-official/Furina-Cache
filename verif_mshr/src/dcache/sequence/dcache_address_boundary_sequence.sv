// address_boundary场景只通过公开CPU和内存IO施加激励，结果由公共检查器判定。
class dcache_address_boundary_sequence extends dcache_scenario_sequence;
    `uvm_object_utils(dcache_address_boundary_sequence)
    function new(string name = "dcache_address_boundary_sequence");
        super.new(name);
    endfunction
    extern virtual task body();
endclass

task dcache_address_boundary_sequence::body();
    bit [31:0] addresses[8] = '{32'h0,32'h3c,32'h40,32'h7c0,32'h7fc,32'h800,32'hfffff800,32'hfffffffc};
    for (int round_index = 0; round_index < 8; round_index++) begin
        foreach (addresses[index]) begin
            access(addresses[index], 1, 'h12560000 + round_index*16 + index);
            access(addresses[index]);
        end
    end
    finish_scenario();
    record_check("all ID values reused", submitted, 128);
endtask
