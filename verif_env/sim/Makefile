#Makefile for simulink the project
#-------------------------------------------------------
export TEST_NAME = Test
DUT = ./dut.f
TB = ./tb.f
UVM_HOME = /home/alicealike1022/tools/uvm/uvm-1.2


WORK_DIR = work
WAVE_DIR = $(WORK_DIR)/wave
LOG_DIR = $(WORK_DIR)/log
RUN_DIR = $(WORK_DIR)/run
CSRC_DIR = $(WORK_DIR)/csrc
SCRIPT_DIR = $(WORK_DIR)/script

SIMV = $(RUN_DIR)/simv
WAVEFORM = $(WAVE_DIR)/wave.fsdb
VCS_COMP_LOG = $(LOG_DIR)/vcs_com.log
VCS_SIM_LOG = $(LOG_DIR)/vcs_sim.log
DUMP_TCL = $(SCRIPT_DIR)/dump_wave.tcl   # 新增：波形 dump 脚本

DIRS = $(WORK_DIR) $(WAVE_DIR) $(RUN_DIR) $(LOG_DIR) $(CSRC_DIR) $(SCRIPT_DIR)
$(DIRS):
	@mkdir -p $@


$(DUMP_TCL): 
	@echo "Generating TCL script for waveform dump..."
	@echo "fsdbDumpfile \"$(WAVEFORM)\"" > $@
	@echo "fsdbDumpvars 0 \"tb_top\"" >> $@
	@echo "run" >> $@
	@echo "TCL script generated: $(DUMP_TCL)"

vcs_all: clean vcs_compile vcs_simulate

vcs_compile: $(DIRS)
	vcs -notice -debug_acc+all -j8 -timescale=1ns/1ps \
        -sverilog -LDFLAGS -rdynamic -full64 \
		+incdir+$(UVM_HOME)/src/ \
		$(UVM_HOME)/src/uvm.sv \
		$(UVM_HOME)/src/dpi/uvm_dpi.cc \
		-Mdir=$(CSRC_DIR) \
        -f $(DUT) -f $(TB) \
        +vcs+lic+wait \
		-kdb \
		-l $(VCS_COMP_LOG) \
		-CFLAGS -DVCS \
		-o $(SIMV)
        
vcs_simulate: $(SIMV) $(DUMP_TCL)
	$(SIMV) \
    +fsdb+autoflush \
	+wave=$(WAVEFORM) \
	-ucli -do $(DUMP_TCL) \
	-l $(VCS_SIM_LOG)

vcs_simulate_verdi: $(SIMV) $(DUMP_TCL)
	$(SIMV) \
    +fsdb+autoflush \
	+wave=$(WAVEFORM) \
	-ucli -do $(DUMP_TCL) \
    -l $(VCS_SIM_LOG) \
	+UVM_VERDI_TRACE="UVM_AWARE+HIER" -gui=verdi

run_verdi:
	verdi -nologo -sv -f $(TB) $(DUT) -ssf $(WAVEFORM) -logdir $(LOG_DIR) &


clean:
	rm -rf $(WORK_DIR) novas.* novas_dump.log ucli.key verdiLog/ inter.fsdb tr_db.log

help:
	@echo "Available targets:"
	@echo "  vcs_all              - 完整流程：清理 + 编译 + 仿真"
	@echo "  vcs_compile          - 仅编译"
	@echo "  vcs_simulate         - 仅仿真（需先编译）"
	@echo "  vcs_simulate_verdi   - 仿真并用 Verdi 打开"
	@echo "  run_verdi            - 单独打开 Verdi 查看波形"
	@echo "  clean                - 清理所有仿真生成的文件"
