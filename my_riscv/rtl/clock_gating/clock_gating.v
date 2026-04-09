module clock_gating (
    input  wire clk_in,     // 输入时钟
    input  wire enable,     // 时钟使能信号
    input  wire rst_n,      // 异步复位，低有效
    output wire clk_out     // 门控后的时钟
);

    // 内部锁存器，用于防止毛刺
    reg enable_latch;
    
    // 使用负沿触发的锁存器锁存使能信号
    // 这样可以使时钟在高电平期间保持稳定
    always @(*) begin
        if (!clk_in) begin  // 时钟低电平时锁存器透明
            enable_latch <= enable;
        end
        // 时钟高电平时锁存器保持原值
    end
    
    // 异步复位锁存器
    always @(negedge rst_n or negedge clk_in) begin
        if (!rst_n) begin
            enable_latch <= 1'b0;
        end
    end
    
    // 时钟输出 = 输入时钟 & 锁存的使能信号
    assign clk_out = clk_in & enable_latch;

endmodule