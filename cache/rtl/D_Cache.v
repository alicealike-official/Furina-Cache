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
    input  wire                             cpu_req,        // CPU访问请求
    input  wire                             cpu_wr_en,      // CPU写使能（1=写，0=读）
    input  wire [DataAddrBus-1 : 0]         cpu_req_addr,   // CPU访问地址
    input  wire [DataWidth-1 : 0]           cpu_wdata,      // CPU写数据
    output wire [DataWidth-1 : 0]           cache_rdata,    // Cache读数据
    output wire                             ready,          // 访问完成信号
    
    // Cache <-> 内存 接口
    output wire                             mem_req,        // 内存请求
    output wire                             mem_wr_en,      // 内存写使能（写回用）
    output wire [DataAddrBus-1 : 0]         mem_addr,       // 内存地址
    output wire [8*Cache_Block_Size-1 : 0]  mem_wdata,      // 写回内存的数据
    input  wire                             mem_resp,       // 内存响应
    input  wire [8*Cache_Block_Size-1 : 0]  mem_rdata       // 内存读数据
);
    localparam Index_Width  = $clog2(Num_Cache_Set);
    localparam Offset_Width = $clog2(Cache_Block_Size);
    localparam Way_Width    = $clog2(Num_Cache_Way);
    localparam Tag_Width    = DataAddrBus - Offset_Width - Index_Width;

    //cache存储内容
    reg                             valid[Num_Cache_Way][Num_Cache_Set];
    reg                             dirty[Num_Cache_Way][Num_Cache_Set];
    reg [Tag_Width-1 : 0]           tag[Num_Cache_Way][Num_Cache_Set];
    reg [8*Cache_Block_Size-1 : 0]  cache_data[Num_Cache_Way][Num_Cache_Set];

    //地址分解
    wire [Index_Width-1 : 0]    index_in;
    wire [Tag_Width-1 : 0]      tag_in;
    wire [Offset_Width-1 : 0]   offset_in;

    assign {tag_in, index_in, offset_in} = cpu_req_addr;


    //命中判断
    wire [Num_Cache_Way-1 : 0]  way_hit;
    wire                        hit_sign;
    wire [Way_Width-1 : 0]      hit_way;

    genvar i;
    generate
        for (i=0; i<Num_Cache_Way; i=i+1) begin
            assign way_hit[i] = valid[i][index_in]&&(tag[i][index_in] == tag_in);
        end
    endgenerate
    assign hit_sign = |way_hit;

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


    //====================状态机定义=============================//
    localparam IDLE         = 2'b00;
    localparam DIRTY_CHECK  = 2'b01;
    localparam WB           = 2'b10;
    localparam MISS_WAIT    = 2'b11;

    reg [1:0] curr_state;
    reg [1:0] next_state;

    //==================================控制信号================================//
    wire                            alloc_enable;
    wire                            miss_done;
    wire                            wb_done;
    wire                            replace_dirty;
    wire                            is_write_back_req;
    wire                            is_cpu_req_valid;
    wire [DataAddrBus-1 : 0]        alloc_addr;
    wire [DataWidth-1 : 0]          hit_rdata;
    wire [DataWidth-1 : 0]          alloc_data;
    wire [Way_Width-1 : 0]          alloc_way;


    assign hit_rdata            = (~cpu_wr_en) ? cache_data[hit_way][index_in][8*offset_in +: DataWidth] : {DataWidth{1'b0}};
    assign alloc_data           = mem_rdata[8*offset_in +: DataWidth];
    assign alloc_addr           = {tag[alloc_way][index_in], index_in, Offset_Width{1'b0}};

    assign alloc_enable         = cpu_req && (curr_state == IDLE && ~hit_sign);
    assign mem_req              = cpu_req && ((cpu_wr_en && (curr_state == IDLE && ~hit_sign)) ||
                                     (~cpu_wr_en && ((curr_state == DIRTY_CHECK) || wb_done))
                                    );
    assign mem_wr_en            = cpu_req && (~cpu_wr_en && replace_dirty);
    assign is_write_back_req    = (~cpu_wr_en && replace_dirty);
    assign is_cpu_req_valid     = ((~cpu_wr_en && (wb_done || curr_state == MISS_WAIT)) || (cpu_wr_en && curr_state == IDLE && ~hit_sign));
    assign mem_addr             = cpu_req ? (
                                    is_write_back_req   ? alloc_addr    :
                                    is_cpu_req_valid    ? cpu_req_addr  :
                                    0) : 0;
    assign mem_wdata            = (is_write_back_req) ? cache_data[alloc_way][index_in] : 0;
    assign ready                = (cpu_req && ((curr_state == IDLE && hit_sign) || miss_done)) || ~cpu_req;
    assign wb_done              = (curr_state == WB && mem_resp);
    assign miss_done            = (curr_state == MISS_WAIT && mem_resp);
    assign replace_dirty        = (curr_state == DIRTY_CHECK && dirty[alloc_way][index_in]);

    assign cache_rdata          = (hit_sign) ? hit_rdata : alloc_data;

    //====================状态机跳转===========================//
    always @(*) begin
        case(curr_state)
            IDLE: begin
                if (!cpu_req || hit_sign) begin
                    next_state = IDLE;
                end

                else if (cpu_wr_en) begin
                    next_state = MISS_WAIT;
                end
                else begin
                    next_state = DIRTY_CHECK;
                end
            end

            DIRTY_CHECK: begin
                next_state = replace_dirty ? WB : MISS_WAIT;
            end

            WB: begin
                next_state = mem_resp ? MISS_WAIT : WB;
            end

            MISS_WAIT: begin
                next_state = mem_resp ? IDLE : MISS_WAIT;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    //===================状态机时序=================//
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
            if(cpu_req && cpu_wr_en && hit_sign && curr_state == IDLE)begin
                cache_data[hit_way][index_in][8*offset_in +: DataWidth]     <= cpu_wdata;
                dirty[hit_way][index_in]                                    <= 1'b1;
            end

            if(miss_done) begin
                valid[alloc_way][index_in] <=1'b1;
                tag[alloc_way][index_in] <= tag_in;
                // cache_data[alloc_way][index_in] <= mem_rdata;
                //dirty[alloc_way][index_in] <= 1'b0;
                if (cpu_wr_en) begin
                    cache_data[alloc_way][index_in] <= 
                        {mem_rdata[8*Cache_Block_Size-1 : 8*offset_in+DataWidth],
                            cpu_wdata,
                        mem_rdata[8*offset_in-1 : 0]};
                    dirty[alloc_way][index_in] <= 1'b1;  // 写操作标记脏
                end

                else begin
                    cache_data[alloc_way][index_in] <= mem_rdata;
                    dirty[alloc_way][index_in] <= 1'b0;
                end
            end
        end 
    end


    //===============FIFO替换策略================//
       
     fifo_counter u_fifo_counter #(
        .Num_Cache_Way(Num_Cache_Way)
    ) (
        .clk(clk),
        .reset(reset),
        .alloc_enable(alloc_enable),
        .replace_way_out(alloc_way)
    );


endmodule 