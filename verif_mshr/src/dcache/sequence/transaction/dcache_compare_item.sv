class dcache_compare_item extends uvm_sequence_item;
    dcache_sample actual;
    dcache_sample expected;
    `uvm_object_utils(dcache_compare_item)
    function new(string name = "dcache_compare_item");
        super.new(name);
        expected = dcache_sample::type_id::create("expected");
    endfunction
endclass
