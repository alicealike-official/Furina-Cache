module I_cache #(
    parameter Num_Cache_Set = 32,
    parameter Cache_Block_Size = 64,
    parameter Num_Cache_Way = 4,
    
    parameter DataAddrBus = 32,
    parameter DataWidth = 32
) (
    input  wire                             clk,
    input  wire                             reset,
    
    // CPU <-> Cache 接口（读写操作）
    input  wire                             cpu_req_valid,  // CPU访问请求
    input  wire [DataAddrBus-1 : 0]         cpu_req_addr,   // CPU访问地址
    output wire [DataWidth-1 : 0]           cache_rdata,    // Cache读数据
    output wire                             cpu_req_ready,          // 访问完成信号
    output wire                             cpu_resp_valid,
    input  wire                             cpu_resp_ready,

    // Cache -> Memory 请求通道
    output wire                             mem_req_valid,    // cache to mem request
    input  wire                             mem_req_ready,    // mem to cache ready
    output wire                             mem_wr_en,        //write/read enable, 1=write, 0=read  
    output wire [DataAddrBus-1 : 0]         mem_addr,         //cache to mem addr

    // Memory -> Cache 响应通道  
    input  wire                             mem_resp_valid,   // mem to cache response
    output wire                             mem_resp_ready,   // cache to mem ready
    input  wire [8*Cache_Block_Size-1 : 0]  mem_rdata
);
    localparam Index_Width      = $clog2(Num_Cache_Set);
    localparam Offset_Width     = $clog2(Cache_Block_Size);
    localparam Way_Width        = $clog2(Num_Cache_Way);
    localparam Tag_Width        = DataAddrBus - Offset_Width - Index_Width;
    localparam Words_Per_Block   = Cache_Block_Size / (DataWidth / 8);


    //-------------------状态定义--------------------//
    localparam IDLE = 0;
    localparam MISS_WAIT = 1;
    reg  curr_state;
    reg  next_state;
    //-------------------状态定义--------------------//

    //cache行
    reg                             valid [Num_Cache_Way][Num_Cache_Set];
    reg [Tag_Width-1 : 0]           tag [Num_Cache_Way][Num_Cache_Set];
    reg [DataWidth-1 : 0]           cache_data [Num_Cache_Way][Num_Cache_Set][Words_Per_Block];


    //索引项
    wire [Index_Width-1:0]              index_in;
    wire [Offset_Width-1:0]             offset_in;
    wire [Tag_Width-1:0]                tag_in;
    wire [$clog2(Words_Per_Block)-1:0]  word_offset;

    //地址分解
    assign {tag_in, index_in, offset_in} = cpu_req_addr;
    assign word_offset = offset_in >> $clog2(DataWidth/8);


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

    //====================内存信号锁存器=============================//
    reg [DataAddrBus-1 : 0]         mem_addr_r;
    // reg [8*Cache_Block_Size-1 : 0]  mem_wdata_r;
    // reg                             mem_wr_en_r;
    //====================内存信号锁存器=============================//



    //================================生成mem握手信号=================================//
    wire mem_resp_handshake; //mem发生handshake
    wire mem_req_handshake; //cache发生handshake


    assign mem_resp_handshake = mem_resp_valid && mem_resp_ready;
    assign mem_req_handshake = mem_req_valid && mem_req_ready;
    //================================生成mem握手信号=================================//



    //================================生成cpu握手信号=================================//
    wire cpu_req_handshake; //表示cache接受到了这个请求，要求保持一个周期时间
    wire cpu_resp_handshake; //表示cache处理完了这个请求，可以发送下一个请求了，要求保持一个周期


    assign cpu_resp_valid = (curr_state == IDLE && hit_sign) || 
                                (curr_state == MISS_WAIT && mem_resp_handshake);
    assign cpu_req_handshake    = cpu_req_valid && cpu_req_ready;
    assign cpu_resp_handshake   = cpu_resp_valid && cpu_resp_ready;
    //================================生成cpu握手信号=================================//



    //==================================alloc信号================================//
    wire [Way_Width-1 : 0]      alloc_way [Num_Cache_Set];
    wire [Way_Width-1 : 0]      curr_alloc_way;//由FIFO counter确认
    //wire [DataAddrBus-1 : 0]    alloc_addr;
    wire [DataWidth-1 : 0]      hit_rdata;
    wire [DataWidth-1 : 0]      alloc_data;


    assign curr_alloc_way   = alloc_way[index_in];
    //assign alloc_addr       = {tag[curr_alloc_way][index_in], index_in, {Offset_Width{1'b0}}};
    assign hit_rdata        = cache_data[hit_way][index_in][word_offset];
    assign alloc_data       = mem_rdata[word_offset*DataWidth +: DataWidth];
    //==================================alloc信号================================//






    // wire alloc_get;//判断是否获得了alloc_way
    // wire alloc_enable_condition;
    // wire [Num_Cache_Set-1 :0] alloc_enable;
    // wire [DataWidth-1 : 0] hit_data;
    // wire [DataWidth-1 : 0] alloc_data;

    // assign hit_data = cache_data[hit_way][index_in][8*offset_in +: DataWidth];
    // assign alloc_data = (alloc_get) ? cache_data[alloc_way][index_in][8*offset_in +: DataWidth] : {DataWidth{1'b0}};


    // assign alloc_get = (state == MISS_WAIT) && mem_resp;//这个表示alloc完成在MISS_WAIT的状态中


    // //内存请求
    // assign mem_addr = (mem_req) ? cpu_req_addr : {DataWidth{1'b0}};
    // assign mem_req = (state == IDLE) && cpu_req && (~hit_sign);

    // //alloc请求
    // assign alloc_enable_condition = (state == IDLE) && cpu_req && (~hit_sign);
    // assign alloc_enable = alloc_enable_condition ? (1 << index_in) ? {Num_Cache_Set{1'b0}};
    // assign alloc_get = (state == MISS_WAIT);

    // //ready信号
    // assign ready = ((state == IDLE) && hit_sign && cpu_req) || ((state == MISS_WAIT) && mem_resp);
    // assign rdata = (hit_sign) ? hit_data : alloc_data;

    



    //================================状态机跳转================================//
    always@(*) begin
        case(curr_state) 
            IDLE: begin
                next_state = (cpu_req_handshake && ~hit_sign) ? MISS_WAIT : IDLE;
            end

            MISS_WAIT: begin
                next_state = (mem_resp_handshake) ? IDLE : MISS_WAIT;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end
    //================================状态机跳转================================//



    //状态机时序
    integer n,p,q;
    always@(posedge clk or negedge reset) begin
        if(!reset) begin
            curr_state <= IDLE;
            for(n=0; n<Num_Cache_Way; n = n+1) begin
                for(p=0; p<Num_Cache_Set; p = p+1) begin
                    valid[n][p] <= 1'b0;
                    tag[n][p] <= {Tag_Width{1'b0}};
                    for(q=0; q<Words_Per_Block; q=q+1) begin
                        cache_data[n][p][q] <= {DataWidth{1'b0}};
                    end
                end
            end
        end

        else begin
            curr_state <= next_state;
            if(curr_state == MISS_WAIT && mem_resp_handshake) begin
                    for (int i = 0; i < Words_Per_Block; i++) begin
                            cache_data[curr_alloc_way][index_in][i] <= 
                            mem_rdata[i*DataWidth +: DataWidth];
                    end
                     
                    // cache_data[alloc_way][index_in] <= mem_data;
                    valid[curr_alloc_way][index_in] <= 1'b1;
                    tag[curr_alloc_way][index_in]   <= tag_in;
            
            end
        end
    end


    //================================生成mem控制信号=================================//
    // 请求Valid信号：Cache有请求要发
    wire mem_req_valid_condition;


    assign mem_req_valid_condition  = (curr_state == IDLE && ~hit_sign);
    assign mem_resp_ready           = (curr_state == MISS_WAIT);

    //================================生成mem控制信号=================================//

    //================================内存信号锁存器更新==========================//
    reg mem_req_valid_r;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mem_req_valid_r <= 1'b0;
        end
        else if (mem_req_valid_condition && !mem_req_valid_r) begin
            mem_req_valid_r <= 1'b1;  // 需要发请求，拉高
        end
        else if (mem_req_valid_r && mem_req_ready) begin
            mem_req_valid_r <= 1'b0;  // 握手成功，清除
        end
    end
    assign mem_req_valid = mem_req_valid_r;

    reg [DataAddrBus-1:0] mem_addr_r;
    always @(posedge clk or negedge reset) begin
        if(!reset) begin
            mem_addr_r <= {DataWidth{1'b0}};
        end

        else begin
            if (mem_req_valid_condition) begin
                mem_addr_r <= {tag_in, index_in, {Offset_Width{1'b0}}};
            end
        end
    end


    assign mem_wr_en = 1'b0;
    assign mem_wdata = {8*Cache_Block_Size{1'b0}};
    assign mem_addr  = mem_addr_r;
  
    //================================内存信号锁存器更新==========================//




    // fifo_counter u_fifo_counter #(
    //     .Num_Cache_Way(Num_Cache_Way)
    // ) (
    //     .clk(clk),
    //     .reset(reset),
    //     .alloc_enable(alloc_enable),
    //     .replace_way_out(alloc_way)
    // );

    // generate
    //     for (genvar set = 0; set < Num_Cache_Set; set++) begin : fifo_inst_gen
    //         fifo_counter #(
    //             .Num_Cache_Way(Num_Cache_Way)
    //         ) u_fifo_counter (
    //             .clk(clk),
    //             .reset(reset),
    //             .alloc_enable(alloc_enable[set]),
    //             .replace_way_out(alloc_way)
    //         );
    //     end
    // endgenerate

    wire                        alloc_enable_condition;//alloc使能
    wire [Num_Cache_Set-1:0]    alloc_enable;//确认alloc使能的哪一路


    assign alloc_enable_condition   = (curr_state == MISS_WAIT) && mem_resp_handshake;
    assign alloc_enable             = alloc_enable_condition ? (32'b1 << index_in) : {Num_Cache_Set{1'b0}};
    //============================FIFO替换策略========================//
    generate
        for (genvar set = 0; set < Num_Cache_Set; set++) begin : fifo_inst_gen
            fifo_counter #(
                .Num_Cache_Way(Num_Cache_Way)
            ) u_fifo_counter (
                .clk(clk),
                .reset(reset),
                .alloc_enable(alloc_enable[set]),
                .replace_way_out(alloc_way[set])
            );
        end
    endgenerate
    //============================FIFO替换策略========================//



    //============================cache to cpu signal===========================//
    assign cpu_req_ready    = (curr_state == IDLE);
    assign cache_rdata      = (hit_sign) ? hit_rdata : alloc_data;
    //============================cache to cpu signal===========================//
endmodule