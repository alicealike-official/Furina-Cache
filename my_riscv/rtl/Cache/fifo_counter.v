module fifo_counter #(
    parameter Num_Cache_Way = 4
)(
    input  wire                                     clk,
    input  wire                                     reset,
    input  wire                                     alloc_enable,           // 缺失信号
    output wire [$clog2(Num_Cache_Way)-1:0]         replace_way_out
);

    localparam Counter_Width = $clog2(Num_Cache_Way);
    // FIFO 指针：指向下一个要替换的路
    reg [Counter_Width-1:0] fifo_ptr;
    
    // 更新 FIFO 指针
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            fifo_ptr <= 0;
        end 
        else if (alloc_enable) begin
            // 缺失时，指针指向下一个路
            if (fifo_ptr == Num_Cache_Way - 1) begin
                fifo_ptr <= 0;
            end 
            else begin
                fifo_ptr <= fifo_ptr + 1;
            end
        end
    end
    
    // 输出要替换的路
    assign replace_way_out = fifo_ptr;
    
endmodule