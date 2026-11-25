class dcache_event_collision_test extends dcache_read_write_overlap_test;
    `uvm_component_utils(dcache_event_collision_test)
    function new(string name = "dcache_event_collision_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
