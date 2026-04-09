// branch_predictor.sv
class branch_predictor #(
    parameter Num_BHT_entries = 64, 
    parameter Num_BTB_entries = 64
    ) extends uvm_component;
    `uvm_object_param_utils(branch_predictor #(Num_BHT_entries, Num_BTB_entries))
    
    virtual dut_interface vif;

    localparam Width_BHT_entries = $clog2(Num_BHT_entries);
    localparam Width_BTB_entries = $clog2(Num_BTB_entries);

    // bit clk;
    // bit reset;
    // bit [InstAddrBus-1 : 0]     EX_pc;                //执行模块执行的pc，用于更新BHT的预测模型
    // bit                         EX_pc_branch_request;  //分支请求有效
    // bit                         EX_pc_branch_is_taken;  //分支实际是否跳转
    // bit[InstAddrBus-1 : 0]      EX_pc_branch_target;     //分支实际目标PC
    // bit                         EX_pc_branch_mispredict;//预测错误信号    

    // bit [InstAddrBus-1 : 0]     IF_pc;                  //译码模块的pc，用于进行预测的pc
    // bit [6:0]                   IF_opcode;
    // bit                         IF_pc_branch_request;     //IF指令分支请求有效（通过opcode判断）

    // bit                         IF_pc_branch_is_taken;    //IF指令分支实际是否跳转（内部信号）
    // bit                         next_pc;
    
    typedef struct {
        bit [1:0] counter;  
    } bht_entry_t;

    bht_entry_t bht[Num_BHT_entries];
    bit [Width_BHT_entries-1 : 0] bht_write_index;
    bit [Width_BHT_entries-1 : 0] bht_read_index;

    typedef struct {
        bit  valid;
        bit [InstAddrBus-1 : 0] source_pc;
        bit [InstAddrBus-1 : 0] target_pc;
    } btb_entry_t;
    
    btb_entry_t btb[Num_BTB_entries];
    bit [Width_BTB_entries-1 : 0] btb_write_entry;
    bit btb_hit;


    bit btb_alloc;
    bit [InstAddrBus-1 : 0] lrsr_q;
    bit [InstAddrBus-1 : 0] allocate_entry;


    function new(string name = "branch_predictor", uvm_parent = parent);
        super.new(name, parent);
    endfunction
    

    extern task run_phase(uvm_phase phase);
    extern task reset();
    extern function void initial_branch_predictor();
    extern function void initial_bht();
    extern function void initial_btb();
    extern function void intial_lrsr_q();
    extern task start_model();
    extern function void get_EX_pc_bht_index();
    extern function void update_bht();
    extern function void update_btb();
    extern function void get_btb_write_entry();
    extern function void reflesh_btb();
    extern function void append_btb();
    extern function void generate_lrsr_q();
    extern function void get_alloc_entry();
    extern function void predict_next_pc();
endclass

task branch_predictor::run_phase(uvm_phase phase);
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

task branch_predictor::reset();
    initial_branch_predictor();
endtask

function void branch_predictor::initial_branch_predictor();
    initial_bht();
    initial_btb();
    intial_lrsr_q();
endfunction

function void branch_predictor::initial_bht();
    for (int i=0; i < Num_BHT_entries; i++) begin
        bht[i] <= 2'b00;//初始预测为强不跳转
    end
endfunction

function void branch_predictor::initial_btb();
    for(int i=0; i < Num_BTB_entries; i++) begin
        btb[i].valid = 0;
        btb[i].btb_source_pc = 0;
        btb[i].btb_target_pc = 0;
    end
endfunction

function void branch_predictor::intial_lrsr_q();
    lrsr_q = 0;
endfunction

task branch_predictor::start_model();
    get_EX_pc_bht_index();
    if(vif.EX_pc_branch_request) begin
        update_bht();
        if (vif.EX_pc_branch_is_taken) begin
            update_btb();
        end
    end
endtask

function void branch_predictor::update_bht();
    if(vif.EX_pc_branch_is_taken) begin
        if(bht[bht_write_index] != 2'b11) begin
            bht[bht_write_index] = bht[bht_write_index]+1;
        end
    end

    else begin
        if(bht[bht_write_index] != 2'b00) begin
            bht[bht_write_index] = bht[bht_write_index]-1;
        end
    end
endfunction

function void branch_predictor::get_EX_pc_bht_index();
    bht_write_index = vif.EX_pc[2-1+Width_BHT_entries: 2];
endfunction

function void branch_predictor::update_btb();
    get_btb_write_entry();
    if(bit_hit) begin
        reflesh_btb();
    end

    else begin
        append_btb();
    end
endfunction

function void branch_predictor::get_btb_write_entry();
    for (int i=0; i < Num_BTB_entries; i++) begin
        if(btb[i].valid && (btb[i].source_pc == vif.EX_pc)) begin
            btb_hit = 1;
            btb_write_entry = i;
        end

        btb_alloc = ~btb_hit;
    end
endfunction

function void branch_predictor::reflesh_btb();
    btb[btb_write_entry].valid = 1;
    btb[btb_write_entry].target_pc = vif.EX_pc_branch_target;
endfunction

function void branch_predictor::append_btb();
    generate_lrsr_q();
    get_alloc_entry();
    btb[btb_alloc_entry].valid = 1;
    btb[btb_alloc_entry].source_pc = vif.EX_pc;
    btb[btb_alloc_entry].target_pc = vif.EX_pc_branch_target;
endfunction

function void branch_predictor::generate_lrsr_q();
    if(btb_alloc) begin
        if (lrsr_q == {WIDTH{1'b1}}) begin
            lrsr_q = 'b0;
        end

        else begin
            lrsr_q = lrsr_q + 1;
        end
    end
endfunction

function void branch_predictor::get_alloc_entry();
    allocate_entry = lrsr_q;
endfunction