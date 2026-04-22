module D_cache#(
    parameter Num_Cache_Set = 32,
    parameter Cache_Block_Size = 64,
    parameter Num_Cache_Way = 4,
    
    parameter DataAddrBus = 32,
    parameter DataWidth = 32
)  (
    // 系统时钟与复位
    input  wire                             clk,
    input  wire                             reset,
    
    // CPU <-> Cache 接口（读写操作）
    input  wire                             cpu_valid,        // CPU访问请求
    input  wire                             cpu_wr_en,      // CPU写使能（1=写，0=读）
    input  wire [DataAddrBus-1 : 0]         cpu_req_addr,   // CPU访问地址
    input  wire [DataWidth-1 : 0]           cpu_wdata,      // CPU写数据
    output wire [DataWidth-1 : 0]           cache_rdata,    // Cache读数据
    output wire                             cpu_ready,          // 访问完成信号

    // Cache -> Memory 请求通道
    output wire                             mem_req_valid,    // cache to mem request
    input  wire                             mem_req_ready,    // mem to cache ready
    output wire                             mem_wr_en,        //write/read enable, 1=write, 0=read  
    output wire [DataAddrBus-1 : 0]         mem_addr,         //cache to mem addr
    output wire [8*Cache_Block_Size-1 : 0]  mem_wdata,

    // Memory -> Cache 响应通道  
    input  wire                             mem_resp_valid,   // mem to cache response
    output wire                             mem_resp_ready,   // cache to mem ready
    input  wire [8*Cache_Block_Size-1 : 0]  mem_rdata
);
    localparam Index_Width  = $clog2(Num_Cache_Set);
    localparam Offset_Width = $clog2(Cache_Block_Size);
    localparam Way_Width    = $clog2(Num_Cache_Way);
    localparam Tag_Width    = DataAddrBus - Offset_Width - Index_Width;

    //===============================cache存储内容=======================//
    reg                             valid[Num_Cache_Way][Num_Cache_Set];
    reg                             dirty[Num_Cache_Way][Num_Cache_Set];
    reg [Tag_Width-1 : 0]           tag[Num_Cache_Way][Num_Cache_Set];
    reg [8*Cache_Block_Size-1 : 0]  cache_data[Num_Cache_Way][Num_Cache_Set];
    //===============================cache存储内容=======================//

    //==============================地址分解===============================//
    wire [Index_Width-1 : 0]    index_in;
    wire [Tag_Width-1 : 0]      tag_in;
    wire [Offset_Width-1 : 0]   offset_in;

    assign {tag_in, index_in, offset_in} = cpu_req_addr;
    //==============================地址分解===============================//


    //==============================命中判断===============================//
    wire [Num_Cache_Way-1 : 0]  way_hit;
    wire                        hit_sign;

    //for priority enconder
    reg [Way_Width-1 : 0]      hit_way;

    genvar i;
    generate
        for (i=0; i<Num_Cache_Way; i=i+1) begin
            assign way_hit[i] = valid[i][index_in]&&(tag[i][index_in] == tag_in);
        end
    endgenerate
    assign hit_sign = |way_hit;
    //==============================命中判断===============================//

    //=============优先编码器==========//
    always @(*) begin
        hit_way = 0;
        if (hit_sign) begin
            for (int i = 0; i < Num_Cache_Way; i = i + 1) begin
                if (way_hit[i])
                    hit_way = i;
            end
        end
    end
    //=============优先编码器==========//

    //====================状态机定义=============================//
    localparam IDLE         = 2'b00;
    localparam DIRTY_CHECK  = 2'b01;
    localparam WB           = 2'b10;
    localparam MISS_WAIT    = 2'b11;

    reg [1:0] curr_state;
    reg [1:0] next_state;
    //====================状态机定义=============================//

    //================================生成cpu握手信号=================================//
    wire cpu_handshake;
    assign cpu_handshake = cpu_valid && cpu_ready;
    //================================生成cpu握手信号=================================//

    //==================================alloc信号================================//

    wire alloc_enable_condition;//alloc使能
    assign alloc_enable_condition = cpu_handshake && (curr_state == IDLE && ~hit_sign);

    wire [Num_Cache_Set-1:0] alloc_enable;//确认alloc使能的哪一路
    assign alloc_enable = alloc_enable_condition ? (1 << index_in) : {Num_Cache_Set{1'b0}};

    wire [Way_Width-1 : 0] alloc_way;//由FIFO counter确认
    wire [DataAddrBus-1 : 0] alloc_addr;
    assign alloc_addr = {tag[alloc_way][index_in], index_in, {Offset_Width{1'b0}}};

    wire [DataWidth-1 : 0] hit_rdata;
    assign hit_rdata = (~cpu_wr_en) ? cache_data[hit_way][index_in][8*offset_in +: DataWidth] : {DataWidth{1'b0}};

    wire [DataWidth-1 : 0] alloc_data;
    assign alloc_data = mem_rdata[8*offset_in +: DataWidth];
    //==================================alloc信号================================//



    //================================辅助判断信号===============================//
    wire is_read_miss;//read miss
    wire is_write_miss;//write miss
    assign is_read_miss = (curr_state == IDLE && ~hit_sign && cpu_handshake && ~cpu_wr_en);   
    assign is_write_miss = (curr_state == IDLE && ~hit_sign && cpu_handshake && cpu_wr_en); 

    wire is_dirty;//判断替换行是否dirty
    assign is_dirty = (curr_state == DIRTY_CHECK && dirty[alloc_way][index_in]); 
    wire is_not_dirty;
    assign is_not_dirty = (curr_state == DIRTY_CHECK && !dirty[alloc_way][index_in]);

    wire mem_resp_handshake; //mem发生handshake
    assign mem_resp_handshake = mem_resp_valid && mem_resp_ready;

    wire mem_req_handshake; //cache发生handshake
    assign mem_req_handshake = mem_req_valid && mem_req_ready;

    wire is_write_back;        // 当前是写回操作
    assign is_write_back = is_dirty || (curr_state == WB && !mem_resp_handshake);

    
    wire wb_done; // 写回完成
    assign wb_done = (curr_state == WB && mem_resp_handshake);

    wire miss_done; // 缺失填充完成
    assign miss_done = (curr_state == MISS_WAIT && mem_resp_handshake);
    //================================辅助判断信号===============================//



    //================================生成mem握手信号=================================//
    // 请求Valid信号：Cache有请求要发
    wire mem_req_valid_condition;

    assign mem_req_valid_condition = is_write_miss || (curr_state == DIRTY_CHECK) || (curr_state == WB && mem_resp_handshake);
    // valid 寄存器
    reg mem_req_valid_r;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mem_req_valid_r <= 1'b0;
        end
        else if (mem_req_valid_r && mem_req_ready) begin
            mem_req_valid_r <= 1'b0;  // 握手成功，清除
        end
        else if (mem_req_valid_condition && !mem_req_valid_r) begin
            mem_req_valid_r <= 1'b1;  // 需要发请求，拉高
        end
    end
    assign mem_req_valid = mem_req_valid_r;

    assign mem_resp_ready = (curr_state == WB) || (curr_state == MISS_WAIT);

    //================================生成mem握手信号=================================//



    //================================生成mem传输信号=================================//
    //读写使能信号，判断cache是否要读写mem
    assign mem_wr_en = is_dirty || (curr_state == WB && !mem_resp_handshake);

    //内存地址信号
    assign mem_addr = (is_write_miss || is_not_dirty || wb_done) ? cpu_req_addr :
                  (is_write_back) ? alloc_addr :
                  32'b0;

    //内存写数据
    assign mem_wdata = cache_data[alloc_way][index_in];  // 写回数据
    //================================生成mem传输信号=================================//






    //============================cache to cpu signal===========================//
    wire not_ready;
    assign not_ready                = (cpu_valid && curr_state == IDLE && ~hit_sign) || 
                                            (curr_state == DIRTY_CHECK) || 
                                            (curr_state == WB) ||
                                            (curr_state == MISS_WAIT && !mem_resp_handshake);
    //assign ready                    = (cpu_req && ((curr_state == IDLE && hit_sign) || miss_done)) || !cpu_req;
    //assign ready                    = !not_ready;
    assign cpu_ready                = (curr_state == IDLE);
    assign cache_rdata              = (hit_sign) ? hit_rdata : alloc_data;
    //============================cache to cpu signal===========================//


    //================================状态机跳转================================//
    always @(*) begin
        case(curr_state)
            IDLE: begin
                if (!cpu_valid || cpu_handshake && hit_sign) begin
                    next_state = IDLE;
                end

                else if (cpu_handshake && cpu_wr_en && ~hit_sign) begin
                    next_state = MISS_WAIT;
                end
                else if (cpu_handshake && ~cpu_wr_en && ~hit_sign)begin
                    next_state = DIRTY_CHECK;
                end

                else begin
                    next_state = IDLE;
                end
            end

            DIRTY_CHECK: begin
                next_state = is_dirty ? WB : MISS_WAIT;
            end

            WB: begin
                next_state = wb_done ? MISS_WAIT : WB;
            end

            MISS_WAIT: begin
                next_state = miss_done ? IDLE : MISS_WAIT;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end
    //================================状态机跳转================================//




    //==================================状态机时序===========================//
    always @(posedge clk or negedge reset) begin
        if(!reset) begin
            integer n,p;
            for(n=0; n<Num_Cache_Way; n=n+1) begin
                for(p=0; p<Num_Cache_Set; p=p+1) begin
                    valid[n][p] <= 1'b0;
                    dirty[n][p] <= 1'b0;
                    tag[n][p]   <= {Tag_Width{1'b0}};
                    cache_data[n][p]  <= {8*Cache_Block_Size{1'b0}};
                end
            end
            curr_state <= IDLE;
        end

        else begin
            curr_state <= next_state;

            if(cpu_handshake && cpu_wr_en && hit_sign && curr_state == IDLE)begin
                cache_data[hit_way][index_in][8*offset_in +: DataWidth]     <= cpu_wdata;
                dirty[hit_way][index_in]                                    <= 1'b1;
            end

            if(miss_done) begin
                valid[alloc_way][index_in] <=1'b1;
                tag[alloc_way][index_in] <= tag_in;
                if (cpu_wr_en) begin
                    cache_data[alloc_way][index_in] <= 
                        (mem_rdata & ~(({DataWidth{1'b1}} << (offset_in * 8)))) |
                        ({cpu_wdata} << (offset_in * 8));
                    dirty[alloc_way][index_in] <= 1'b1;  // 写操作标记脏
                end

                else begin
                    cache_data[alloc_way][index_in] <= mem_rdata;
                    dirty[alloc_way][index_in] <= 1'b0;
                end
            end
        end 
    end
    //==================================状态机时序===========================//

    //============================FIFO替换策略========================//
    generate
        for (genvar set = 0; set < Num_Cache_Set; set++) begin : fifo_inst_gen
            fifo_counter #(
                .Num_Cache_Way(Num_Cache_Way)
            ) u_fifo_counter (
                .clk(clk),
                .reset(reset),
                .alloc_enable(alloc_enable[set]),
                .replace_way_out(alloc_way)
            );
        end
    endgenerate
    //============================FIFO替换策略========================//
endmodule 