interface ahb3_master_interface(
    input HCLK,
    input HRESETn
);  
    //用户接口（usr）
    logic                   usr_en;                      //用户使能
    logic                   usr_write;                   //写使能
    logic [2:0]             usr_burst;             //用户设置的突出传输类型
    logic [addr_width-1:0]  usr_addr;   //传输地址
    logic [data_width-1:0]  usr_wdata;  //写数据
    logic [data_width-1:0]  usr_rdata; //读数据
    logic                   done;                   //完成信号
    logic                   error;                  //报错信号
    //AHB接口（H）
    logic                   HREADY;                      //从机准备信号
    logic                   HRESP;                       //从机响应信号
    logic [data_width-1:0]  HRDATA;     //读数据
    logic                   HWRITE;                 //写使能
    logic [2:0]             HSIZE;           //写数据或读数据类型
    logic [2:0]             HBURST;          //突发传输
    logic [1:0]             HTRANS;           //传输状态
    logic [addr_width-1:0]  HADDR; //传输地址
    logic [data_width-1:0]  HWDATA //写数据
endinterface