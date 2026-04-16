interface clk_rst_interface(
        output clk,
        output rst_n
);

        logic clk_drv = 'z;
        logic rst_n_drv = 'z;

        assign clk = clk_drv;
        assign rst_n = rst_n_drv;

        //-------------------modport----------------//
        modport driver(
                output clk_drv,
                output clk,
                output rst_n_drv,
                output rst_n
        );

        modport monitor(
                input clk,
                input rst_n
        );
        //-------------------modport----------------//


        //-------------------concurrent checking----------------//
        bit first_reset_started = 0;

        initial begin
                wait($isunknown({clk,rst_n}) == 1'b0);
                fork
                        forever @(clk or rst_n) begin
                                assert($isunknown({clk, rst_n}) == 1'b0);
                        end

                        begin
                                wait (rst_n == 1'b0);
                                first_reset_started = 1;
                        end
                join
        end
        //-------------------concurrent checking----------------//

endinterface
