#Makefile for simulink the project
#-------------------------------------------------------
export TEST_NAME =
DUT = ./dut.f
TB = ./tb.f
UVM_HOME = ../../verif_env/uvm-1.2

#可配置的线程数
THREADS ?= 10
SIM_ARGS ?=
SVA_DEFINES ?=


WORK_DIR = work/
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
	@echo "fsdbDumpvars 0 \"mshr_tb_top\"" >> $@
	@echo "run" >> $@
	@echo "TCL script generated: $(DUMP_TCL)"

vcs_all: clean vcs_compile vcs_simulate

vcs_compile: $(DIRS)
	@rm -f $(CSRC_DIR)/mshr_dpi.o
	vcs -notice -debug_acc+all -j$(THREADS) -timescale=1ns/1ps \
        -sverilog -LDFLAGS -rdynamic -full64 \
		+incdir+$(UVM_HOME)/src/ \
		$(UVM_HOME)/src/uvm.sv \
		$(UVM_HOME)/src/dpi/uvm_dpi.cc \
		../dpi/mshr_dpi.cpp \
		-Mdir=$(CSRC_DIR) \
		-cm line+cond+fsm+branch+tgl+assert \
  		-cm_dir $(WORK_DIR)/simv.vdb \
        -f $(DUT) -f $(TB) -top mshr_tb_top $(SVA_DEFINES) \
		-kdb \
		-l $(VCS_COMP_LOG) \
		-CFLAGS "-DVCS -std=c++17" \
		-o $(SIMV)
        
vcs_simulate: $(SIMV) $(DUMP_TCL)
	$(SIMV) \
    +fsdb+autoflush \
	+wave=$(WAVEFORM) \
	$(if $(strip $(TEST_NAME)),+UVM_TESTNAME=$(TEST_NAME)) $(SIM_ARGS) \
	-cm line+cond+fsm+branch+tgl+assert \
	-cm_dir  $(WORK_DIR)/simv.vdb \
	-cm_name $(if $(strip $(TEST_NAME)),$(TEST_NAME),mshr_base_test) \
	-ucli -do $(DUMP_TCL) \
	-l $(VCS_SIM_LOG)


run_verdi:
	verdi -nologo -sv -f $(TB) -f $(DUT) -ssf $(WAVEFORM) -logdir $(LOG_DIR) &


clean:
	rm -rf $(WORK_DIR) novas.* novas_dump.log ucli.key verdiLog/ inter.fsdb tr_db.log script/regression_logs urgReport cm.log .fsm.sch.verilog.xml

merge_cov:
	urg -dir $(WORK_DIR)/simv.vdb

help:
	@echo "Available targets:"
	@echo "  vcs_all              - 完整流程：清理 + 编译 + 仿真"
	@echo "  vcs_compile          - 仅编译"
	@echo "  vcs_simulate         - 仅仿真（需先编译）"
	@echo "  run_verdi            - 单独打开 Verdi 查看波形"
	@echo "  clean                - 清理所有仿真生成的文件"

# MSHR独立生成目录；RTL与参数包来自同一Scala配置。
MSHR_ENTRIES ?= 4
MSHR_MAX_PENDING ?= 4
generate:
	cd ../../Design/DCacheMSHR && sbt "runMain furina.dcache.MshrVerificationVerilog ../../verif_mshr/generated/mshr $(MSHR_ENTRIES) $(MSHR_MAX_PENDING)"

run: vcs_simulate

# 独立SV/C++ ABI检查，使用相同参数包，不实例化DUT。
check_dpi: $(DIRS)
	@mkdir -p $(WORK_DIR)/dpi
	vcs -full64 -sverilog -timescale=1ns/1ps \
		+incdir+../src/mshr ../generated/mshr/mshr_params_pkg.sv \
		../test/adapter/mshr_dpi_check.sv ../dpi/mshr_dpi.cpp \
		-CFLAGS "-std=c++17" -top mshr_dpi_check \
		-Mdir=$(WORK_DIR)/dpi/csrc -o $(WORK_DIR)/dpi/simv -l $(WORK_DIR)/dpi/compile.log
	$(WORK_DIR)/dpi/simv -l $(WORK_DIR)/dpi/run.log

check_memory:
	python3 -B ./script/check_mshr_memory_timing.py

check_framework:
	python3 -B ./script/run_mshr_framework.py

.PHONY: generate run vcs_all vcs_compile vcs_simulate run_verdi clean merge_cov help check_dpi check_memory check_framework
