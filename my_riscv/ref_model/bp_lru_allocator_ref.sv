// bp_lru_allocator.sv
class bp_lru_allocator #(parameter DEPTH = 64) extends uvm_component;
    `uvm_object_param_utils(bp_lru_allocator #(DEPTH))
    
    virtual dut_interface vif;
    localparam WIDTH = $clog2(DEPTH);
    bit alloc_enable;
    bit [WIDTH-1 : 0] allocate_entry;

    // LRU tracking
    bit [WIDTH-1:0] lrsr_q;
    
    function new(string name = "bp_lru_allocator", uvm_parent = parent);
        super.new(name, parent);
    endfunction
    


    extern task run_phase(uvm_phase phase);
    extern task reset();
    extern function void initial_alloc();
    extern task start_model();
    extern function void generate_lrsr_q();
    extern function void get_alloc_entry();
    extern function void enable_allocator(input bit alloc_enable_i);
    extern function bit [WIDTH-1 : 0] return_result();
endclass


task bp_lru_allocator::run_phase(uvm_phase phase);
        fork
            forever begin
                @(posedge vif.clk or negedge vif.reset);
                if (vif.reset) begin
                    reset();
                end 
                else begin
                    start_model();
                end
            end
        join
endtask

task bp_lru_allocator::reset();
    initial_alloc();
endtask

function void bp_lru_allocator::initial_alloc();
    lrsr_q = 'b0;
endfunction

task bp_lru_allocator::start_model();
    generate_lrsr_q();
    get_alloc_entry();
endtask

function void bp_lru_allocator::generate_lrsr_q();
    if(alloc_enable) begin
        if (lrsr_q == {WIDTH{1'b1}}) begin
            lrsr_q = 'b0;
        end

        else begin
            lrsr_q = lrsr_q + 1;
        end
    end
endfunction

function void bp_lru_allocator::get_alloc_entry();
    allocate_entry = lrsr_q;
endfunction

function void bp_lru_allocator::enable_allocator(input bit alloc_enable_i);
    alloc_enable = alloc_enable_i;
endfunction

function void bp_lru_allocator::return_result();
    return allocate_entry;
endfunction