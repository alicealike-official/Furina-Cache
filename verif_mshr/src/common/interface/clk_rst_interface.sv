interface clk_rst_interface(output wire clk, output wire rst_n);
    logic clk_drv = 0;
    logic rst_n_drv = 0;
    assign clk = clk_drv;
    assign rst_n = rst_n_drv;
endinterface
