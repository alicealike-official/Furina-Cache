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
+incdir+../src/cache/bind
+incdir+../src/cache/component
+incdir+../src/cache/component/agent
+incdir+../src/cache/component/driver
+incdir+../src/cache/component/monitor
+incdir+../src/cache/component/scoreboard
+incdir+../src/cache/interface
+incdir+../src/cache/model
+incdir+../src/cache/pkg
+incdir+../src/cache/sequence
+incdir+../src/cache/sequence/transaction
+incdir+../src/cache/sequence/basic
+incdir+../src/cache/sequence/function_check
+incdir+../src/cache/sequence/state_management
//-----------cache-----------//

//---------------------------//
//    testbench files
//---------------------------//

//-----------interface-------//
../src/common/interface/clk_rst_interface.sv
../src/cache/interface/cache_interface.sv
../src/cache/interface/cache_debug_interface.sv
//-----------interface-------//

//-----------bind-------//
../src/cache/bind/bind_cache.sv
../src/cache/bind/cache_assertions.sv
//-----------bind-------//

//-----------package---------//
../src/common/pkg/clk_rst_pkg.sv
../src/cache/pkg/cache_pkg.sv
//-----------package---------//

//---------reference model--------//
../src/cache/model/d_cache_model.sv
//---------reference model--------//

//---------scoreboard--------//
../src/cache/component/scoreboard/cpu_stimulus_scoreboard.sv
../src/cache/component/scoreboard/mem_req_scoreboard.sv
../src/cache/component/scoreboard/cache_data_scoreboard.sv
//---------scoreboard--------//

//---------environment-------//
../src/cache/component/cache_environment.sv
//---------environment-------//


//-------------test----------//
../test/common/clock_smoke_test.sv

../test/cache/basic/cache_basic_test.sv

../test/cache/function_check/cache_read_hit_test.sv
../test/cache/function_check/cache_read_miss_test.sv
../test/cache/function_check/cache_write_hit_test.sv
../test/cache/function_check/cache_write_miss_test.sv
../test/cache/function_check/cache_write_read_test.sv


../test/cache/state_management/cache_tag_match_test.sv
//-------------test----------//


//-------------top-----------//
../tb/tb_top.sv
//-------------top-----------//

// //-------------------------------mem test------------------------------//
// ../tb/mem_tb.sv

