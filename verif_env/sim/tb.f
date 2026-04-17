//---------------------------//
//    incdir file path
//---------------------------//

//-----------clk_rst-----------//
+incdir+../src/common
+incdir+../src/common/component
+incdir+../src/common/config
+incdir+../src/common/define
+incdir+../src/common/interface
+incdir+../src/common/model
+incdir+../src/common/pkg
//-----------clk_rst-----------//


//-----------cache-----------//
+incdir+../src/cache
+incdir+../src/cache/component
+incdir+../src/cache/component/agent
+incdir+../src/cache/component/driver
+incdir+../src/cache/interface
+incdir+../src/cache/model
+incdir+../src/cache/pkg
+incdir+../src/cache/sequence
+incdir+../src/cache/sequence/transaction
//-----------cache-----------//

//---------------------------//
//    testbench files
//---------------------------//

//-----------interface-------//
../src/common/interface/clk_rst_interface.sv
../src/cache/interface/cache_interface.sv
//-----------interface-------//


//-----------package---------//
../src/common/pkg/clk_rst_pkg.sv
../src/cache/pkg/cache_pkg.sv
//-----------package---------//


//---------environment-------//
../src/cache/component/cache_environment.sv
//---------environment-------//


//-------------test----------//
../test/common/clock_smoke_test.sv
../test/cache/cache_basic_test.sv
//-------------test----------//


//-------------top-----------//
../tb/tb_top.sv
//-------------top-----------//

