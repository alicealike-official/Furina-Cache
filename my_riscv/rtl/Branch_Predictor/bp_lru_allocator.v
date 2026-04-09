module bp_lru_allocator #(
    parameter DEPTH = 32
)
(
    input clk,
    input reset,
    input alloc_enable,
    output [$clog2(DEPTH)-1 : 0] alloc_entry
);
    localparam WIDTH = $clog2(DEPTH);
    reg [WIDTH-1 : 0] lfsr_q;

    always @ (posedge clk or negedge reset) begin
        if (reset)
            lfsr_q <= {WIDTH{1'b0}};
        else if (alloc_enable) begin
            if (lfsr_q == {WIDTH{1'b1}}) begin
                lfsr_q <= {WIDTH{1'b0}};
            end else begin
                lfsr_q <= lfsr_q + 1;
            end 
        end 
    end

    assign alloc_entry = lfsr_q[WIDTH-1 : 0];
endmodule