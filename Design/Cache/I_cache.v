module I_cache #(
    parameter Num_Cache_Set = 32,
    parameter Cache_Block_Size = 64,
    parameter Num_Cache_Way = 4,
    
    parameter DataAddrBus = 32,
    parameter DataWidth = 32
) (
    //sys io
    input wire clk,
    input wire reset,
    //cpu to cache
    input wire cpu_req,
    input wire [DataAddrBus-1 : 0] cpu_req_addr,
    //cache to mem
    output wire  mem_req,
    input wire  mem_resp,
    output wire  [DataAddrBus-1 : 0] mem_addr,
    input wire  [8*Cache_Block_Size-1 : 0] mem_data,
    //cache to cpu
    output wire rdata,
    output wire ready
);
    localparam Set_Index = $clog2(Num_Cache_Set);
    localparam Way_index = $clog2(Num_Cache_Way);
    localparam Offset_Index = $clog2(Cache_Block_Size);
    localparam Tag_Index = DataAddrBus - Set_Index - Offset_Index;

    //索引项
    wire [Set_Index-1 : 0]      index_in;
    wire [Offset_Index-1 : 0]   offset_in;
    wire [Tag_Index-1 : 0]      tag_in;

    //地址分解
    assign {tag_in, index_in, offset_in} = cpu_req_addr;
    //cache行
    reg                             valid [Num_Cache_Way][Num_Cache_Set];
    reg [Tag_Index-1 : 0]           tag [Num_Cache_Way][Num_Cache_Set];
    reg [8*Cache_Block_Size-1 : 0]  cache_data [Num_Cache_Way][Num_Cache_Set];

    //命中判断
    wire hit_sign;
    wire [Way_index-1 : 0] hit_way;
    wire [Way_index-1 : 0] alloc_way;

    //判断组命中
    wire [Num_Cache_Way-1 : 0] way_hits;
    genvar way_idx;
    generate
        for(way_idx = 0; way_idx < Num_Cache_Way; way_idx = way_idx + 1) begin
            assign way_hits[way_idx] = valid[way_idx][index_in] && (tag[way_idx][index_in] == tag_in);
            assign hit_way = (way_hits[way_idx]) ? way_idx : 0;
        end
    endgenerate
    assign hit_sign = |way_hits;


    wire alloc_get;//判断是否获得了alloc_way
    wire alloc_enable_condition;
    wire [Num_Cache_Set-1 :0] alloc_enable;
    wire [DataWidth-1 : 0] hit_data;
    wire [DataWidth-1 : 0] alloc_data;

    assign hit_data = cache_data[hit_way][index_in][8*offset_in +: DataWidth];
    assign alloc_data = (alloc_get) ? cache_data[alloc_way][index_in][8*offset_in +: DataWidth] : {DataWidth{1'b0}};


    assign alloc_get = (state == MISS_WAIT) && mem_resp;//这个表示alloc完成在MISS_WAIT的状态中


    //内存请求
    assign mem_addr = (mem_req) ? cpu_req_addr : {DataWidth{1'b0}};
    assign mem_req = (state == IDLE) && cpu_req && (~hit_sign);

    //alloc请求
    assign alloc_enable_condition = (state == IDLE) && cpu_req && (~hit_sign);
    assign alloc_enable = alloc_enable_condition ? (1 << index_in) ? {Num_Cache_Set{1'b0}};
    assign alloc_get = (state == MISS_WAIT);

    //ready信号
    assign ready = ((state == IDLE) && hit_sign && cpu_req) || ((state == MISS_WAIT) && mem_resp);
    assign rdata = (hit_sign) ? hit_data : alloc_data;

    
    //-----------------------miss情况下的状态机---------------------//
    //------状态定义-----//
    localparam IDLE = 0;
    localparam MISS_WAIT = 1;


    reg  state;
    reg  next_state;

    always@(*) begin
        case(state) 
            IDLE: begin
                next_state = (cpu_req && ~hit_sign) ? MISS_WAIT : IDLE;
            end

            MISS_WAIT: begin
                next_state = (mem_resp) ? IDLE : MISS_WAIT;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    //状态机时序
    integer n,p;
    always@(posedge clk or negedge reset) begin
        if(reset) begin
            state <= IDLE;
            for(n=0; n<Num_Cache_Way; n = n+1) begin
                for(p=0; p<Num_Cache_Set; p = p+1) begin
                    valid[n][p] <= 1'b0;
                    tag[n][p] <= {Tag_Index{1'b0}};
                    cache_data[n][p] <= {8*Cache_Block_Size{1'b0}};
                end
            end
        end

        else begin
            state <= next_state;
            if(state == MISS_WAIT && mem_resp) begin
                    cache_data[alloc_way][index_in] <= mem_data;
                    valid[alloc_way][index_in] <= 1'b1;
                    tag[alloc_way][index_in] <= tag_in;
            end
        end
    end

    // fifo_counter u_fifo_counter #(
    //     .Num_Cache_Way(Num_Cache_Way)
    // ) (
    //     .clk(clk),
    //     .reset(reset),
    //     .alloc_enable(alloc_enable),
    //     .replace_way_out(alloc_way)
    // );

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
endmodule