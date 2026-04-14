module ahb_top(
    input HCLK;
    input HRESETn;
    input usr_en,                      //用户使能
    input usr_write,                   //写使能
    input [2:0] usr_burst,             //用户设置的突出传输类型
    input [addr_width-1:0] usr_addr,   //传输地址
    input [data_width-1:0] usr_wdata,  //写数据
    output reg [data_width-1:0] usr_rdata, //读数据
    output reg done,                   //完成信号
    output reg error,                  //报错信号
);

wire hready;
wire hresp;
wire [31:0] hdata;
wire hwrite;
wire [2:0] hsize;
wire [2:0] hburst;
wire [1:0] htrans;
wire [31:0] haddr;
wire [31:0] hwdata;


ahb_master u_ahb_master(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .usr_en(usr_en),
    .usr_write(usr_write),
    .usr_burst(usr_burst),
    .usr_addr(usr_addr),
    .usr_wdata(usr_wdata),
    .usr_rdata(usr_rdata),
    .done(done),
    .error(error),

    .HREADY(hready),
    .HRESP(hresp), 
    .HRDATA(hdata),
    .HWRITE(hwrite),
    .HSIZE(hsize),
    .HBURST(hburst),
    .HTRANS(htrans), 
    .HADDR(haddr),
    .HWDATA(hwdata)
);

ahb_slave u_ahb_slave(
    .HCLK(HCLK),
    .HRESETn(HRESETn),
    .HWRITE(hwrite),
    .HTRANS(htrans),
    .HBURST(hburst),
    .HSIZE(hsize),
    .HADDR(haddr),
    .HWDATA(hwdata),
    .HREADY(),

    .HRESP(hresp),
    .HREADYOUT(hready),
    .HRDATA(hdata)
);

endmodule