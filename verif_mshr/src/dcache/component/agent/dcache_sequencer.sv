class dcache_sequencer extends uvm_sequencer #(dcache_transaction);
    dcache_activity_monitor observations;
    dcache_probe_monitor probe_monitor;
    dcache_config cfg;
    // 原C++ SparseMemory封装，由环境传入，供sequence预置后端数据。
    dcache_memory_store memory;
    `uvm_component_utils(dcache_sequencer)
    function new(string name = "dcache_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
