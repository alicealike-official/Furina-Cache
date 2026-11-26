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
	@echo "fsdbDumpvars 0 \"dcache_tb_top\"" >> $@
	@echo "run" >> $@
	@echo "TCL script generated: $(DUMP_TCL)"

vcs_all: clean vcs_compile vcs_simulate

vcs_compile: $(DIRS)
	@rm -f $(CSRC_DIR)/dcache_dpi.o $(CSRC_DIR)/mshr_dpi.o $(CSRC_DIR)/wbb_dpi.o
	vcs -notice -debug_acc+all -j$(THREADS) -timescale=1ns/1ps \
        -sverilog -LDFLAGS -rdynamic -full64 \
		+incdir+$(UVM_HOME)/src/ \
		$(UVM_HOME)/src/uvm.sv \
		$(UVM_HOME)/src/dpi/uvm_dpi.cc \
		../dpi/dcache_dpi.cpp ../dpi/mshr_dpi.cpp ../dpi/wbb_dpi.cpp \
		-Mdir=$(CSRC_DIR) \
		-cm $(COVERAGE_METRICS) $(COVERAGE_OPTIONS) \
		-cm_dir $(COVERAGE_DATABASE) \
        -f $(DUT) -f $(TB) -top dcache_tb_top $(SVA_DEFINES) \
		-kdb \
		-l $(VCS_COMP_LOG) \
		-CFLAGS "-DVCS -std=c++17" \
		-o $(SIMV)
        
vcs_simulate: $(SIMV) $(DUMP_TCL)
	$(SIMV) \
    +fsdb+autoflush \
	+wave=$(WAVEFORM) \
	$(if $(strip $(TEST_NAME)),+UVM_TESTNAME=$(TEST_NAME)) $(SIM_ARGS) \
	-cm $(COVERAGE_METRICS) \
	-cm_dir $(COVERAGE_DATABASE) \
	-cm_name $(if $(strip $(TEST_NAME)),$(TEST_NAME),dcache_base_test) \
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
	@echo "  perf                 - 独立DCache性能矩阵及彩色报告"
	@echo "  clean                - 清理所有仿真生成的文件"

run: vcs_simulate

generate:
	python3 -B script/prepare_dcache.py

check_compile:
	$(MAKE) vcs_compile DUT=stub.f SVA_DEFINES=+define+DCACHE_PORT_STUB WORK_DIR=work/compile_only/

check_dpi:
	@mkdir -p work/dpi
	vcs -full64 -sverilog -timescale=1ns/1ps \
	    +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm.sv $(UVM_HOME)/src/dpi/uvm_dpi.cc \
	    -f tb.f -f stub.f ../test/dcache/dcache_dpi_check.sv ../dpi/dcache_dpi.cpp ../dpi/mshr_dpi.cpp ../dpi/wbb_dpi.cpp \
	    -top dcache_dpi_check +define+DCACHE_PORT_STUB -CFLAGS "-DVCS -std=c++17" \
	    -Mdir=work/dpi/csrc -o work/dpi/simv -l work/dpi/compile.log
	work/dpi/simv -l work/dpi/run.log

check_framework:
	python3 -B script/run_dcache_framework.py

# 独立性能矩阵；保持原模型、scoreboard与断言，结果按运行时间单独保存。
perf:
	python3 -B script/run_dcache_perf.py
