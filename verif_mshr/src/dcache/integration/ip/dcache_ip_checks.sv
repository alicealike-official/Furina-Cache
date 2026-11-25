// 顶层统一承载两个被动IP检查环境，没有IP sequencer/driver，也没有第二个内存驱动。
class dcache_ip_checks extends uvm_env;
    dcache_mshr_checks mshr;
    dcache_wbb_checks wbb;
    `uvm_component_utils(dcache_ip_checks)
    function new(string name = "dcache_ip_checks", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mshr = dcache_mshr_checks::type_id::create("mshr", this);
        wbb = dcache_wbb_checks::type_id::create("wbb", this);
    endfunction
endclass
