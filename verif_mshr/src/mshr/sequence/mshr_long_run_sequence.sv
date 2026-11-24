// 复用random场景的驱动和检查记录，专门设置本case的场景范围。
class mshr_long_run_sequence extends mshr_random_sequence;
    `uvm_object_utils(mshr_long_run_sequence)

    function new(string name = "mshr_long_run_sequence");
        super.new(name);
        rounds = 1024;
        force_full_slots = 1;
    endfunction
endclass
