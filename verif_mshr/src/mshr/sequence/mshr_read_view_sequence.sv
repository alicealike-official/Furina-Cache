// 复用merge_matrix场景的驱动和检查记录，专门设置本case的场景范围。
class mshr_read_view_sequence extends mshr_merge_matrix_sequence;
    `uvm_object_utils(mshr_read_view_sequence)

    function new(string name = "mshr_read_view_sequence");
        super.new(name);
        history_only = 1;
    endfunction
endclass
