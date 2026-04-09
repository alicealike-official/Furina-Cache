simSetSimulator "-vcssv" -exec "./v_sim/simv" -args \
           "+fsdb+autoflush -l v_sim/vcs_sim.log +UVM_VERDI_TRACE=UVM_AWARE+HIER" \
           -uvmDebug on -simDelim
debImport "-i" "-simflow" "-dbdir" "./v_sim/simv.daidir"
srcTBInvokeSim
srcTBRunSim
srcTBSimReset
wvCreateWindow
srcHBSelect "tb_mem.dut" -win $_nTrace1
srcHBSelect "tb_mem.dut" -win $_nTrace1
srcHBSelect "tb_mem" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_mem" -delim "."
srcHBSelect "tb_mem" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "address" -line 7 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcTBRunSim
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
srcTBSimReset
srcTBRunSim
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomIn -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "clk" -line 4 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "rom_read_data" -line 20 -pos 2 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "memory_read" -line 21 -pos 2 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "memory_write" -line 22 -pos 2 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "memory_read" -line 21 -pos 2 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "funct3" -line 23 -pos 2 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvSetRadix -win $_nWave3 -format Bin
srcDeselectAll -win $_nTrace1
srcSelect -signal "written_data" -line 27 -pos 2 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
wvSetCursor -win $_nWave3 24656.361474 -snap {("G1" 6)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "written_address" -line 28 -pos 2 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 7 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 6)}
srcHBSelect "tb_mem.dut" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_mem.dut" -delim "."
srcHBSelect "tb_mem.dut" -win $_nTrace1
wvZoom -win $_nWave3 36527.942925 48551.724138
wvZoomOut -win $_nWave3
wvSetCursor -win $_nWave3 40066.451665 -snap {("G1" 5)}
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 6 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 5)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "memory_read" -line 26 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "funct3" -line 30 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 6 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 5)}
srcDeselectAll -win $_nTrace1
srcSelect -word -line 31 -pos 5 -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -word -line 31 -pos 10 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "address\[1\]" -line 47 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "half_sel" -line 49 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "extended_mask" -line 116 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "half_sel" -line 48 -pos 1 -win $_nTrace1
srcSearchString "half_sel" -win $_nTrace1 -next -case
srcSearchString "half_sel" -win $_nTrace1 -next -case
srcSearchString "half_sel" -win $_nTrace1 -next -case
srcDeselectAll -win $_nTrace1
srcSelect -signal "register_file_write_data" -line 55 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -win $_nTrace1 -range {52 52 13 16 1 1} -backward
srcDeselectAll -win $_nTrace1
wvSetCursor -win $_nWave3 49639.201392 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 39917.237986 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 49982.329513 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 44949.783749 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 50325.457633 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 44835.407709 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 49867.953473 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 40145.990066 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 44835.407709 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 40145.990066 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 45178.535829 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 39688.485906 -snap {("G1" 5)}
wvSetCursor -win $_nWave3 44835.407709 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 49982.329513 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 44606.655629 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 49867.953473 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 45064.159789 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 54900.499236 -snap {("G1" 2)}
wvSetCursor -win $_nWave3 44492.279589 -snap {("G1" 2)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "half_sel\[15\]" -line 55 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
wvZoom -win $_nWave3 37744.093225 45521.663950
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomIn -win $_nWave3
wvZoomIn -win $_nWave3
wvZoomOut -win $_nWave3
wvZoom -win $_nWave3 48311.568927 52084.754249
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
srcTBRunSim
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomIn -win $_nWave3
wvZoomIn -win $_nWave3
wvZoomOut -win $_nWave3
wvZoom -win $_nWave3 89626.608603 108651.578876
srcHBSelect "tb_mem.dut" -win $_nTrace1
srcSetScope -win $_nTrace1 "tb_mem.dut" -delim "."
srcHBSelect "tb_mem.dut" -win $_nTrace1
wvSelectSignal -win $_nWave3 {( "G1" 10 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 9)}
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 8)}
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 7)}
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 6)}
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 5)}
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvCut -win $_nWave3
wvSetPosition -win $_nWave3 {("G2" 0)}
wvSetPosition -win $_nWave3 {("G1" 4)}
srcDeselectAll -win $_nTrace1
srcSelect -signal "memory_write" -line 8 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "written_data" -line 14 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "register_file_write_data" -line 12 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
wvSetCursor -win $_nWave3 99896.925493 -snap {("G1" 6)}
wvShowFilterTextField -win $_nWave3 -on
srcDeselectAll -win $_nTrace1
srcSelect -signal "register_file_write_data" -line 12 -pos 1 -win $_nTrace1
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcSearchString "register_file_write_data" -win $_nTrace1 -next -case
srcDeselectAll -win $_nTrace1
srcSelect -signal "register_file_read_data\[7:0\]" -line 73 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "data_memory_write_data" -line 73 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
debExit
