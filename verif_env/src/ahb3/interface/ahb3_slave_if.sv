interface ahb3_slave_interface(
    input HCLK,
    input HRESETn
);
    logic                   HWRITE;
    logic [1:0]             HTRANS;
    logic [2:0]             HBURST;
    logic [2:0]             HSIZE;
    logic [addr_width-1:0]  HADDR;
    logic [data_width-1:0]  HWDATA;
    logic                   HREADY;

    logic                   HRESP;
    logic                   HREADYOUT;
    logic [data_width-1:0]  HRDATA;
endinterface