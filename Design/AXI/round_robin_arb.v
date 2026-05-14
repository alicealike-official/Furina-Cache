module round_robin_arb #(
    parameter N = 8          // 请求数量
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                enable,       // 仲裁使能（脉冲）
    input  wire [N-1:0]        request,      // 请求位向量
    output reg  [$clog2(N)-1:0] grant        // 选中的请求索引
);

    reg [$clog2(N)-1:0] last_grant;          // 上一次选中的位置

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant      <= 0;
            last_grant <= 0;
        end else if (enable && (|request)) begin
            // 从 last_grant 的下一个位置开始查找
            for (i = 0; i < N; i = i + 1) begin
                // 计算循环索引：(last_grant + 1 + i) % N
                if (request[(last_grant + 1 + i) % N]) begin
                    grant      <= (last_grant + 1 + i) % N;
                    last_grant <= (last_grant + 1 + i) % N;
                    break;                     // 找到第一个就退出
                end
            end
        end
    end

endmodule