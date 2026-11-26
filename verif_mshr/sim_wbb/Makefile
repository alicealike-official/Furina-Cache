#Makefile for simulink the project
#-------------------------------------------------------
export TEST_NAME =
DUT = ./dut.f
# Coverage collection can use an isolated database and DUT-only instrumentation.
COVERAGE_METRICS ?= line+cond+fsm+branch+tgl+assert
COVERAGE_OPTIONS ?=
COVERAGE_DATABASE ?= $(WORK_DIR)/simv.vdb
TB = ./tb.f
UVM_HOME = ../../verif_env/uvm-1.2

#可配置的线程数
THREADS ?= 10
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
	@echo "fsdbDumpvars 0 \"tb_top\"" >> $@
	@echo "run" >> $@
	@echo "TCL script generated: $(DUMP_TCL)"

vcs_all: clean vcs_compile vcs_simulate

vcs_compile: $(DIRS)
	vcs -notice -debug_acc+all -j$(THREADS) -timescale=1ns/1ps \
        -sverilog -LDFLAGS -rdynamic -full64 \
		+incdir+$(UVM_HOME)/src/ \
		$(UVM_HOME)/src/uvm.sv \
		$(UVM_HOME)/src/dpi/uvm_dpi.cc \
		../dpi/wbb_dpi.cpp \
		-Mdir=$(CSRC_DIR) \
		-cm $(COVERAGE_METRICS) $(COVERAGE_OPTIONS) \
		-cm_dir $(COVERAGE_DATABASE) \
        -f $(DUT) -f $(TB) $(SVA_DEFINES) \
		-kdb \
		-l $(VCS_COMP_LOG) \
		-CFLAGS "-DVCS -std=c++17" \
		-o $(SIMV)
        
vcs_simulate: $(SIMV) $(DUMP_TCL)
	$(SIMV) \
    +fsdb+autoflush \
	+wave=$(WAVEFORM) \
	$(if $(strip $(TEST_NAME)),+UVM_TESTNAME=$(TEST_NAME)) \
	-cm $(COVERAGE_METRICS) \
	-cm_dir $(COVERAGE_DATABASE) \
	-cm_name $(if $(strip $(TEST_NAME)),$(TEST_NAME),wbb_base_test) \
	-ucli -do $(DUMP_TCL) \
	-l $(VCS_SIM_LOG)


run_verdi:
	verdi -nologo -sv -f $(TB) -f $(DUT) -ssf $(WAVEFORM) -logdir $(LOG_DIR) &


clean:
	rm -rf $(WORK_DIR) novas.* novas_dump.log ucli.key verdiLog/ inter.fsdb tr_db.log script/regression_logs urgReport cm.log .fsm.sch.verilog.xml

merge_cov:
	urg -dir $(COVERAGE_DATABASE)

help:
	@echo "Available targets:"
	@echo "  vcs_all              - 完整流程：清理 + 编译 + 仿真"
	@echo "  vcs_compile          - 仅编译"
	@echo "  vcs_simulate         - 仅仿真（需先编译）"
	@echo "  run_verdi            - 单独打开 Verdi 查看波形"
	@echo "  clean                - 清理所有仿真生成的文件"

# Generate RTL and SV parameters from the same Scala CacheConfig.
WBB_ENTRIES ?= 4
generate:
	cd ../../Design/DCacheMSHR && sbt "runMain furina.dcache.WbbVerificationVerilog ../../verif_mshr/generated/wbb $(WBB_ENTRIES)"

# Standalone SV/C++ ABI check; does not run a DUT functional case.
check_dpi: $(DIRS)
	vcs -full64 -sverilog -timescale=1ns/1ps \
		+incdir+../src/wbb ../generated/wbb/wbb_params_pkg.sv \
		../test/adapter/dpi_adapter_check.sv ../dpi/wbb_dpi.cpp \
		-CFLAGS "-std=c++17" -top dpi_adapter_check \
		-Mdir=$(WORK_DIR)/dpi_csrc -o $(RUN_DIR)/dpi_check \
		-l $(LOG_DIR)/dpi_compile.log
	$(RUN_DIR)/dpi_check -l $(LOG_DIR)/dpi_check.log

# IO assertion self-test: synthetic legal/illegal traces; no DUT implementation.
check_sva:
	python3 ./script/check_wbb_sva.py
