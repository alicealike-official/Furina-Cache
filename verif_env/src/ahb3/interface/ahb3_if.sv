`include "ahb3_master_if.sv"
`include "ahb3_slave_if.sv"

`define AHB_MAX_SLAVE_NUM 16
interface ahb3_interface(
    input HCLK,
    input HRESETn
);
    ahb3_master_interface master_if(
        .HCLK(HCLK),
        .HRESETn(HRESETn)
    );

    ahb3_slave_interface slave_if[`AHB_MAX_SLAVE_NUM] (
        .HCLK(HCLK),
        .HRESETn(HRESETn)
    );
    
    extern function void check_slave_define(int idx);
    extern function virtual ahb3_slave_interface get_slave_if(int idx);

endinterface

function void ahb3_interface::check_slave_define(int idx);
    if (idx>=`AHB_MAX_SLAVE_NUM) begin
      $display("[FATAL] ahb3_interface: the slave index %0d has not been defined, check the AHB_MAX_SLAVE_NUM define", idx);
      $finish;
    end
endfunction

function virtual ahb3_slave_interface ahb3_interface::get_slave_if(int idx);
    check_slave_define(idx);

    // Max: 16
    case(idx)
      00: return slave_if[00];
      01: return slave_if[01];
      02: return slave_if[02];
      03: return slave_if[03];
      04: return slave_if[04];
      05: return slave_if[05];
      06: return slave_if[06];
      07: return slave_if[07];
      08: return slave_if[08];
      09: return slave_if[09];
      10: return slave_if[10];
      11: return slave_if[11];
      12: return slave_if[12];
      13: return slave_if[13];
      14: return slave_if[14];
      15: return slave_if[15];
    endcase
endfunction