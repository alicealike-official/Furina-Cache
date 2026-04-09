module D_cache #(
    parameter Num_Cache_Set  = 32,    // Cache组数量
    parameter Cache_Block_Size = 64,   // Cache块大小（字节）
    parameter Num_Cache_Way  = 4,      // 相联路数
    
    parameter DataAddrBus    = 32,     // 地址位宽
    parameter DataWidth      = 32      // 数据位宽
) (
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

    // 地址位段计算
    localparam Offset_Width = $clog2(Cache_Block_Size);  // 块内偏移
    localparam Index_Width  = $clog2(Num_Cache_Set);     // 组索引
    localparam Way_Width    = $clog2(Num_Cache_Way);     // 路索引
    localparam Tag_Width    = DataAddrBus - Index_Width - Offset_Width; // 标记位

    // 地址分解
    wire [Tag_Width-1 : 0]     tag_in;
    wire [Index_Width-1 : 0]   index_in;
    wire [Offset_Width-1 : 0]  offset_in;
    assign {tag_in, index_in, offset_in} = cpu_req_addr;

    // ==================== Cache存储结构 ====================
    // 有效位 | 标记位 | 脏位（写回核心） | 数据块
    reg                             valid  [Num_Cache_Way][Num_Cache_Set];
    reg [Tag_Width-1 : 0]           tag    [Num_Cache_Way][Num_Cache_Set];
    reg                             dirty  [Num_Cache_Way][Num_Cache_Set]; // 脏位：1=需写回
    reg [8*Cache_Block_Size-1 : 0]  data   [Num_Cache_Way][Num_Cache_Set];

    // ==================== 命中判断逻辑 ====================
    wire [Num_Cache_Way-1 : 0]  way_hit;
    wire                        hit;
    wire [Way_Width-1 : 0]      hit_way;

    // 逐路判断命中
    genvar i;
    generate
        for(i=0; i<Num_Cache_Way; i=i+1) begin : HIT_CHECK
            assign way_hit[i] = valid[i][index_in] && (tag[i][index_in] == tag_in);
        end
    endgenerate

    assign hit = |way_hit; // 组内任意一路命中即为总命中

    // 编码命中的路号
    onehot_to_bin #(.ONEHOT_WIDTH(Num_Cache_Way)) u_hit_way (
        .onehot(way_hit),
        .bin(hit_way)
    );

    // ==================== 替换算法：LRU路选择 ====================
    wire [Way_Width-1 : 0] replace_way; // 待替换的路
    lru_ctrl #(
        .SET_NUM(Num_Cache_Set),
        .WAY_NUM(Num_Cache_Way)
    ) u_lru (
        .clk(clk),
        .reset(reset),
        .access_en(hit && cpu_req), // 命中时更新LRU
        .access_way(hit_way),
        .index(index_in),
        .lru_way(replace_way)
    );

    // ==================== 状态机定义（写回必需） ====================
    localparam IDLE        = 2'd0; // 空闲
    localparam MISS_WAIT   = 2'd1; // 缺失：等待内存读
    localparam WB_WAIT     = 2'd2; // 写回：等待脏块写入内存

    reg [1:0] curr_state;
    reg [1:0] next_state;

    // ==================== 控制信号 ====================
    wire        miss            = cpu_req && ~hit; // 访问缺失
    wire        replace_dirty   = valid[replace_way][index_in] && dirty[replace_way][index_in]; // 待替换路是脏块
    wire        wb_done         = (curr_state == WB_WAIT) && mem_resp; // 写回完成
    wire        miss_done       = (curr_state == MISS_WAIT) && mem_resp; // 读缺失完成

    // 内存控制
    assign mem_req     = (curr_state == IDLE && miss) || (curr_state == WB_WAIT);
    assign mem_wr_en   = (curr_state == WB_WAIT); // 写回状态时写内存
    assign mem_addr    = mem_wr_en ? {tag[replace_way][index_in], index_in, {Offset_Width{1'b0}}} : cpu_req_addr;
    assign mem_wdata   = data[replace_way][index_in]; // 写回脏块数据

    // CPU响应控制
    assign ready       = (curr_state == IDLE && hit && cpu_req) || miss_done || wb_done;
    assign cache_rdata = hit ? data[hit_way][index_in][8*offset_in +: DataWidth] : {DataWidth{1'b0}};

    // ==================== 状态机时序逻辑 ====================
    always @(posedge clk or negedge reset) begin
        if(!reset) begin
            curr_state <= IDLE;
            // 复位：所有位清零
            integer n, p;
            for(n=0; n<Num_Cache_Way; n=n+1) begin
                for(p=0; p<Num_Cache_Set; p=p+1) begin
                    valid[n][p] <= 1'b0;
                    dirty[n][p] <= 1'b0;
                    tag[n][p]   <= {Tag_Width{1'b0}};
                    data[n][p]  <= {8*Cache_Block_Size{1'b0}};
                end
            end
        end
        else begin
            curr_state <= next_state;

            // ============== 写操作：写命中直接修改Cache，置脏位 ==============
            if(curr_state == IDLE && hit && cpu_req && cpu_wr_en) begin
                data[hit_way][index_in][8*offset_in +: DataWidth] <= cpu_wdata;
                dirty[hit_way][index_in] <= 1'b1; // 写操作必置脏
            end

            // ============== 读缺失完成：加载新块到Cache，清零脏位 ==============
            if(miss_done) begin
                valid[replace_way][index_in] <= 1'b1;
                tag[replace_way][index_in]   <= tag_in;
                data[replace_way][index_in]  <= mem_rdata;
                dirty[replace_way][index_in] <= 1'b0; // 新加载块无脏数据
            end
        end
    end

    // ==================== 状态机组合逻辑 ====================
    always @(*) begin
        next_state = curr_state;
        case(curr_state)
            IDLE: begin
                if(miss) begin
                    // 缺失：先判断是否需要写回脏块
                    next_state = replace_dirty ? WB_WAIT : MISS_WAIT;
                end
            end
            MISS_WAIT: begin
                if(miss_done) next_state = IDLE; // 读完成返回空闲
            end
            WB_WAIT: begin
                if(wb_done) next_state = MISS_WAIT; // 写回完成后读内存
            end
        endcase
    end

endmodule

// 辅助模块：独热码转二进制码
module onehot_to_bin #(parameter ONEHOT_WIDTH=4) (
    input  wire [ONEHOT_WIDTH-1:0]  onehot,
    output wire [$clog2(ONEHOT_WIDTH)-1:0] bin
);
    integer i;
    reg [$clog2(ONEHOT_WIDTH)-1:0] tmp;
    always @(*) begin
        tmp = 0;
        for(i=0; i<ONEHOT_WIDTH; i=i+1) begin
            if(onehot[i]) tmp = i;
        end
    end
    assign bin = tmp;
endmodule

// 辅助模块：LRU替换控制器（简化版）
module lru_ctrl #(
    parameter SET_NUM=32,
    parameter WAY_NUM=4
) (
    input  wire                        clk,
    input  wire                        reset,
    input  wire                        access_en,
    input  wire [$clog2(WAY_NUM)-1:0]  access_way,
    input  wire [$clog2(SET_NUM)-1:0]  index,
    output wire [$clog2(WAY_NUM)-1:0]  lru_way
);
    reg [$clog2(WAY_NUM)-1:0] lru_reg[SET_NUM-1:0];
    assign lru_way = lru_reg[index];
    
    always @(posedge clk or negedge reset) begin
        if(!reset) lru_reg[index] <= 0;
        else if(access_en) lru_reg[index] <= access_way;
    end
endmodule