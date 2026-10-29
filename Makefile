# gemmini-int8-npu Makefile
# 常用目标: lint / sim_mac / sim_fifo / sim_array / sim_array8 / regression / clean

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

RTL := rtl
TB := tb

MAC_SRCS  := $(RTL)/mac.sv
FIFO_SRCS := $(RTL)/fifo.sv
PE_SRCS   := $(RTL)/pe.sv
SYS4_SRCS := $(RTL)/pe.sv $(RTL)/systolic_array.sv
SYS8_SRCS := $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/systolic_8x8.sv

LOGDIR := logs

export PYTHONPATH := $(abspath $(TB)):$(abspath verification)

# 需要 cocotb 的仿真目标统一走这里 (递归 make 携带各自变量)
# 每个目标独立 SIM_BUILD, 避免共用 sim_build/sim.vvp 造成源文件变更不重编译
.PHONY: sim_mac sim_fifo sim_array sim_array8

sim_mac:
	$(MAKE) sim COCOTB_TOPLEVEL=mac SIM_BUILD=sim_build/$@ \
	  COCOTB_TEST_MODULES=tb_mac VERILOG_SOURCES="$(MAC_SRCS)"

sim_fifo:
	$(MAKE) sim COCOTB_TOPLEVEL=fifo SIM_BUILD=sim_build/$@ \
	  COCOTB_TEST_MODULES=tb_fifo VERILOG_SOURCES="$(FIFO_SRCS)"

sim_array:
	$(MAKE) sim COCOTB_TOPLEVEL=systolic_array SIM_BUILD=sim_build/$@ \
	  COCOTB_TEST_MODULES=tb_systolic VERILOG_SOURCES="$(SYS4_SRCS)"

sim_array8:
	$(MAKE) sim COCOTB_TOPLEVEL=systolic_8x8 SIM_BUILD=sim_build/$@ \
	  COCOTB_TEST_MODULES=tb_systolic VERILOG_SOURCES="$(SYS8_SRCS)"

# regress: 依次跑全部仿真, 每次输出独立日志
# 注: 不能命名为 regression —— cocotb Makefile.inc 中 sim 依赖同名目标, 会互相覆盖
.PHONY: regress
regress:
	@mkdir -p $(LOGDIR)
	@set -e; for t in sim_mac sim_fifo sim_array sim_array8; do \
	  echo "===== $$t ====="; \
	  $(MAKE) $$t 2>&1 | tee $(LOGDIR)/$$t.log || { \
	    echo "REGRESSION FAIL at $$t (log: $(LOGDIR)/$$t.log)"; exit 1; }; \
	done
	@echo "REGRESSION PASS"

.PHONY: lint
lint:
	verilator --lint-only -Wall -Wno-fatal $(RTL)/*.sv

.PHONY: synth
synth:
	@command -v yosys >/dev/null 2>&1 || { \
	  echo "yosys not installed (W9 任务, 见 docs/05_ppa_sta_report.md)"; exit 1; }
	@echo "TODO: yosys flow 脚本 (synthesis/flow/)"

.PHONY: mrproper
mrproper:
	rm -rf __pycache__ $(TB)/__pycache__ verification/__pycache__ sim_build results.xml
	rm -rf $(LOGDIR)

include $(shell cocotb-config --makefiles)/Makefile.sim
