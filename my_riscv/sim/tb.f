//---------------------------//
//    incdir file path
//---------------------------//

//-----------clk_rst-----------//
+incdir+../uvm_test/clk_rst
+incdir+../uvm_test/clk_rst/clk_config
+incdir+../uvm_test/clk_rst/clk_component
//-----------ID-----------//

//-----------ID-----------//
+incdir+../uvm_test/ID
+incdir+../uvm_test/ID/sequence
+incdir+../uvm_test/ID/config
+incdir+../uvm_test/ID/component
//-----------ID-----------//

//---------------------------//
//    testbench files
//---------------------------//

//-----------interface-------//
../uvm_test/interface/ID_interface.sv
../uvm_test/interface/clk_rst_interface.sv
//-----------interface-------//


//-----------package---------//
../uvm_test/packages/ID_pkg.sv
../uvm_test/packages/clk_rst_pkg.sv
//-----------package---------//


//---------environment-------//
../uvm_test/env/ID_env.sv
//---------environment-------//


//-------------test----------//
../uvm_test/ID/test/test.sv
//-------------test----------//


//-------------top-----------//
../uvm_test/tb_top.sv
//-------------top-----------//

