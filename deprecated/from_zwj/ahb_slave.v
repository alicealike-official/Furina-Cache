module ahb_slave #(
    parameter addr_width = 32,
    parameter data_width = 32,
    parameter [1:0] salve_addr = 11,
)(
    input HCLK,
    input HRESETn,
    input HWRITE,
    input [1:0] HTRANS,
    input [2:0] HBURST,
    input [2:0] HSIZE,
    input [addr_width-1:0] HADDR,
    input [data_width-1:0] HWDATA,
    input HREADY,

    output HRESP,
    output HREADYOUT,
    output [data_width-1:0] HRDATA
);

reg [31:0] memory [0:1023];
reg [addr_width-1:0] latched_addr;
reg [data_width-1:0] latched_wdata;
reg latched_write;
wire my_sel;
wire valid;

assign my_sel = (HADDR[addr_width-1:addr_width-2]==salve_addr)?1:0;
assign valid = my_sel&&HREADY&&(HTRANS==2'b10||HTRANS==2'b11);

always @(posedge HCLK or negedge HRESETn) begin
    if(!HRESETn)begin
        latched_addr <= 32'd0;
        latched_wdata <= 32'd0;
        latched_write <= 1'b0;
    end
    else if(valid) begin
        latched_addr <= HADDR;
        latched_wdata <= HWDATA;
        latched_write <= HWRITE;
    end
end

always @(posedge HCLK)begin
    if(latched_write&&HREADY) memory[latched_addr] <= latched_wdata;
end
assign HRDATA = (!latched_write)?memory[latched_addr]:{data_width{1'b0}};
assign HRESP = 1'b0;
assign HREADYOUT = 1'b1;

endmodule