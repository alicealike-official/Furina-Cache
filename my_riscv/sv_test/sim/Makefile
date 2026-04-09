#Makefile for simulink the project
#-------------------------------------------------------
export TEST_NAME = Test
DUT = dut.f
TB = tb.f
UVM_HOME = /home/alicealike1022/tools/uvm/uvm-1.2

SIM_DIR = v_sim
waveform = wave.fsdb
 


$(SIM_DIR):
	@mkdir -p $@

vcs_all: clean vcs_compile vcs_simulate
vcs_compile: $(SIM_DIR)
	vcs -notice -debug_acc+all -j8 -timescale=1ns/1ps \
        -sverilog -LDFLAGS -rdynamic -full64 \
		+incdir+$(UVM_HOME)/src/ \
		$(UVM_HOME)/src/uvm.sv \
		$(UVM_HOME)/src/dpi/uvm_dpi.cc \
		-Mdir=./v_sim/csrc \
        -f $(DUT) -f $(TB) \
        +vcs+lic+wait \
		-kdb \
        -l ./v_sim/vcs_com.log \
		-CFLAGS -DVCS \
		-o v_sim/simv
        
vcs_simulate: $(SIM_DIR)/simv
	./v_sim/simv \
    +fsdb+autoflush \
    -l v_sim/vcs_sim.log 

vcs_simulate_verdi: $(SIM_DIR)/simv
	./v_sim/simv \
    +fsdb+autoflush \
    -l v_sim/vcs_sim.log \
	+UVM_VERDI_TRACE="UVM_AWARE+HIER" -gui=verdi

run_verdi:
	verdi -nologo -sv -f $(TB) -ssf $(waveform) -logdir ./v_sim &


clean:
	rm -rf $(SIM_DIR) novas.* novas_dump.log ucli.key
