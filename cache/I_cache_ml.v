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
    input wire cpu_req;
    input wire [DataAddrBus-1 : 0] cpu_req_addr,
    //cache to mem
    output wire  mem_req,
    input wire  mem_resp;
    output reg  [DataAddrBus-1 : 0] mem_addr,
    input wire  [8*Cache_Block_Size-1 : 0] mem_data,
    //cache to cpu
//    output reg  [DataWidth-1 : 0] rdata,
    output wire rdata,
    output wire ready
);
    localparam Set_Index = $clog2(Num_Cache_Set);
    localparam Way_index = $clog2(Num_Cache_Way);
    localparam Offset_Index = $clog2(Cache_Block_Size);
    localparam Tag_Index = DataAddrBus - Set_Index - Offset_Index;
    
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

    genvar way_idx;
    generate
        for(way_idx = 0; way_idx < Num_Cache_Way; way_idx = way_idx + 1) begin : hit_detect
            wire way_hit = valid[way_idx][index_in] && (tag[way_idx][index_in] == tag_in);
            assign hit_sign = way_hit ? 1'b1 : 0;
            assign hit_way = way_hit ? way_idx : 0;
        end
    endgenerate

    wire alloc_get;
    assign alloc_get = (state == MISS_WAIT) && mem_resp;
    assign mem_req = (state == IDLE) && cpu_req && (~hit_sign);
    wire [DataWidth-1 : 0] hit_data;
    wire [DataWidth-1 : 0] alloc_data;

    
    assign hit_data = cache_data[hit_way][index_in][8*offset_in +: DataWidth];
    assign alloc_data = (alloc_get) ? cache_data[alloc_way][index_in][8*offset_in +: DataWidth] : {DataWidth{1'b0}};
    assign rdata = (hit_sign) ? hit_data : alloc_data;
    assign ready = (state == IDLE && cpu_req && hit_sign) || (state == MISS_WAIT && mem_resp);
    //-----------------------miss情况下的状态机---------------------//
    //------状态定义-----//
    localparam IDLE = 0;
    localparam MISS_WAIT = 1;
    localparam FILL = 2;


    reg [1:0] state;
    reg [1:0] next_state;
    reg alloc_enable;

    always@(*) begin
        case(state) 
            IDLE: begin
                next_state = (cpu_req && ~hit_sign) ? MISS_WAIT : IDLE;
            end

            MISS_WAIT: begin
                next_state = (mem_resp) ? FILL : MISS_WAIT;
            end

            FILL: begin
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end


    integer n,p;
    //状态机时序
    always@(posedge clk or negedge reset) begin
        if(reset) begin
            state <= IDLE;
            mem_req <= 1'b0;
            rdata <= {DataWidth{1'b0}};
            mem_addr <= {DataAddrBus{1'b0}};
            ready <= 1'b1;
            alloc_enable <= 1'b0;

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
        end
    end
    
    always@(posedge clk) begin
        case(state) 
            IDLE: begin
                if(cpu_req && ~hit_sign) begin
                    mem_req <= 1'b1;
                    mem_addr <= cpu_req_addr;
                    alloc_enable <= 1'b1;
                end
            end

            MISS_WAIT: begin
                if(mem_resp) begin
                    cache_data[alloc_way][index_in] <= mem_data;
                    valid[alloc_way][index_in] <= 1'b1;
                    tag[alloc_way][index_in] <= tag_in;
                    mem_req <= 1'b0;
                    mem_addr <= {DataAddrBus{1'b0}};
                    alloc_enable <= 1'b0;
                    ready <= 1'b1;
                end
            end

            // FILL: begin
            //     rdata <= cache_data[alloc_way][index_in][8*offset_in +: DataWidth];
            //     ready <= 1'b1;
            // end
        endcase
    end

    fifo_counter u_fifo_counter #(
        Num_Cache_Way
    ) (
        .clk(clk),
        .reset(reset),
        .alloc_enable(alloc_enable),
        .replace_way_out(alloc_way)
    );

endmodule