//---------------------------//
//    incdir file path
//---------------------------//

//-----------clk_rst-----------//
+incdir+../src/common/component
+incdir+../src/common/config
+incdir+../src/common/interface
+incdir+../src/common/model
+incdir+../src/common/pkg
//-----------clk_rst-----------//

//-----------cache-----------//

//-----------cache-----------//

//---------------------------//
//    testbench files
//---------------------------//

//-----------interface-------//
../src/common/interface/clk_rst_interface.sv
//-----------interface-------//


//-----------package---------//
../src/common/pkg/clk_rst_pkg.sv
//-----------package---------//


//---------environment-------//
//../uvm_test/env/ID_env.sv
//---------environment-------//


//-------------test----------//
../test/common/clock_smoke_test.sv
//-------------test----------//


//-------------top-----------//
../tb/tb_top.sv
//-------------top-----------//

