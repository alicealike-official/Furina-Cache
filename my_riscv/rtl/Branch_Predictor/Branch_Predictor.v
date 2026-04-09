module Branch_Predictor #(
    parameter InstAddrBus = 32,
    parameter Num_BHT_entries = 64,
    parameter Num_BTB_entries = 64
)
(
    input wire clk,
    input wire reset,
    input wire[InstAddrBus-1 : 0]   EX_pc,                    //执行模块执行的pc，用于更新BHT的预测模型
    input wire                 EX_pc_branch_request,     //分支请求有效
    input wire                 EX_pc_branch_is_taken,    //分支实际是否跳转
    input wire[InstAddrBus-1 : 0]   EX_pc_branch_target,      //分支实际目标PC
    input wire                 EX_pc_branch_mispredict,  //预测错误信号    

    input wire [InstAddrBus-1 : 0]  IF_pc,                    //译码模块的pc，用于进行预测的pc
    input wire [6:0]           IF_opcode,
    input wire                 IF_pc_branch_request,     //IF指令分支请求有效（通过opcode判断）

    output                     IF_pc_branch_is_taken,    //IF指令分支实际是否跳转（内部信号）
    output                     next_pc                  //预测的下一条指令
);

    wire [InstAddrBus-1 : 0] IF_pc_plus_4;
    assign IF_pc_plus_4 = IF_pc + 4;
    //----------------BHT-----------------//
    localparam Width_BHT_entries = $clog2(Num_BHT_entries);
    reg [1:0] bht_bim_list [Num_BHT_entries-1 : 0];     //Entries个数的2位FSM
    
    //Update BHT
    wire [Width_BHT_entries-1 : 0] bht_write_index = EX_pc[2+Width_BHT_entries-1 : 2];

    integer n;
    always @(posedge clk or negedge  reset) begin
        if (reset) begin
            // initialize the bht
            for (n = 0; n < Num_BHT_entries; n = n + 1) begin
                bht_bim_list[n] <= 2'b00;   //初始预测不跳转
            end
        end 
        
        else begin
            if (EX_pc_branch_request) begin        //EX的pc是branch
                if((EX_pc_branch_is_taken == 1'b1) && (bht_bim_list[bht_write_index] < 2'd3)) begin
                    bht_bim_list[bht_write_index] <= bht_bim_list[bht_write_index] + 2'd1;
                end 
                
                else if ((EX_pc_branch_is_taken  == 1'b0) && (bht_bim_list[bht_write_index] > 2'd0)) begin
                    bht_bim_list[bht_write_index] <= bht_bim_list[bht_write_index] - 2'd1;
                end
            end
        end
    end


    //Predict
    wire [Width_BHT_entries-1 : 0] bht_read_index    = IF_pc[2+Width_BHT_entries-1 : 2];
    wire                           bht_predict_taken = bht_bim_list[bht_read_index][1];
    //----------------BHT-----------------//


    //----------------------BTB------------------------//
    wire IF_pc_is_branch;
    localparam Width_BTB_entries = $clog2(Num_BTB_entries);
    //BTB array
    reg                     btb_valid_list [Num_BTB_entries-1 : 0];
    reg [InstAddrBus-1 : 0] btb_source_pc_list  [Num_BTB_entries-1 : 0];
    reg [InstAddrBus-1 : 0] btb_target_pc_list  [Num_BTB_entries-1 : 0];

    assign IF_pc_is_branch = (IF_opcode == `OPCODE_BRANCH);

    //look up
    reg btb_is_matched;
    reg [InstAddrBus-1 : 0] btb_target_pc;
    //reg [Width_BTB_entries-1 : 0] btb_rd_entry;

    integer k;
    always @(*) begin
        btb_is_matched = 0;
        btb_target_pc = IF_pc_plus_4;
        //btb_rd_entry = {Width_BTB_entries{1'b0}};

        if (IF_pc_is_branch) begin
            //search btb
            for (k = 0; k < NUM_BTB_ENTRIES; k = k + 1) begin
                if ( (btb_source_pc_list[k] == IF_pc) && btb_is_valid_list[k] ) begin    //matched pc
                    btb_is_matched   = 1'b1;
                    btb_target_pc = btb_target_pc_list[k];
                    //btb_rd_entry   = k;
                end
            end
        end
    end

    //update btb
    reg [Width_BTB_entries-1 : 0] btb_write_entry;
    reg [Width_BTB_entries-1 : 0] btb_alloc_entry;

    reg btb_hit;        //1为命中，0为没有命中
    reg btb_alloc_req;  //1为申请alloc

    integer q;
    
    //确定命中的entry
    always@(*) begin
        btb_write_entry = {Width_BTB_entries{1'b0}};
        btb_hit = 0;
        btb_alloc_req = 0;

        if(EX_pc_branch_request && EX_pc_branch_is_taken) begin
            for (q = 0; q < Num_BTB_entries; q = q+1) begin
                if ((btb_source_pc_list[q] == EX_pc) && btb_valid_list[q]) begin
                    btb_hit = 1;
                    btb_write_entry = q;
                end    
            end
            btb_alloc_req = ~btb_hit;
        end
    end
    //生成alloc_entry
    bp_lru_allocator
    #(
        .DEPTH(Num_BTB_entries)
    ) u_lru
    (
        .clk(clk),
        .reset(reset),
        .alloc_enable(btb_alloc_req),
        .alloc_entry(btb_alloc_entry)
    );

    //根据entry更新条目
    integer p;

    always@(posedge clk or negedge reset) begin
        if (reset) begin
            for (p = 0; p < Num_BTB_entries; p = p+1) begin
                btb_valid_list[p] <= 0;
                btb_source_pc_list[p] <= {InstAddrBus{1'b0}};
                btb_target_pc_list[p] <= {InstAddrBus{1'b0}};
            end
        end

        else begin
            if (EX_pc_branch_request && EX_pc_branch_is_taken) begin
                if (btb_hit  == 1'b1) begin //更新BTB内容
                    btb_target_pc_list[btb_write_entry] <= EX_pc_branch_target;
                end

                else begin //分配
                    btb_valid_list[btb_alloc_entry] <= 1'b1;
                    btb_source_pc_list[btb_alloc_entry] <= EX_pc;
                    btb_target_pc_list[btb_alloc_entry] <= EX_pc_branch_target;
                end
            end
        end
    end
    //----------------------BTB------------------------//

    //-----------------------BP----------------------//
    assign IF_pc_branch_is_taken = (btb_is_matched && bht_predict_taken) ? 1 : 0;
    assign next_pc = (btb_is_matched && bht_predict_taken) ? btb_target_pc : IF_pc_plus_4;
endmodule