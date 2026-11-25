class dcache_long_run_sequence extends dcache_random_sequence;
    `uvm_object_utils(dcache_long_run_sequence)
    function new(string name = "dcache_long_run_sequence");
        super.new(name);
        request_count = 65536;
    endfunction
endclass
