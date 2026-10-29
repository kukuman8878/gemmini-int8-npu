# gemmini-int8-npu Makefile
# 目标: lint / sim_mac / sim_mac_v / sim_pe / sim_pe16 / sim_skew / sim_fifo / sim_array / sim_array8 / regress / synth / mrproper

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

RTL := rtl
TB := tb

MAC_SRCS  := $(RTL)/mac.sv
FIFO_SRCS := $(RTL)/fifo.sv
PE_SRCS   := $(RTL)/pe.sv
SYS4_SRCS := $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/systolic_4x4.sv
SYS8_SRCS := $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/systolic_8x8.sv

LOGDIR := logs
REGRESSION_TESTS := sim_mac sim_mac_v sim_pe sim_pe16 sim_skew sim_controller sim_top sim_fifo sim_array sim_array8

export PYTHONPATH := $(abspath $(TB)):$(abspath verification)

# 需要 cocotb 的仿真目标统一走这里 (递归 make 携带各自变量)
# 每个目标独立 SIM_BUILD 与 COCOTB_RESULTS_FILE, 避免共用构建产物造成源文件变更不重编译
.PHONY: sim_mac sim_mac_v sim_pe sim_pe16 sim_skew sim_controller sim_top sim_fifo sim_array sim_array8

sim_mac:
	$(MAKE) sim COCOTB_TOPLEVEL=mac SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_mac VERILOG_SOURCES="$(MAC_SRCS)"

sim_fifo:
	$(MAKE) sim COCOTB_TOPLEVEL=fifo SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_fifo VERILOG_SOURCES="$(FIFO_SRCS)"

sim_array:
	$(MAKE) sim COCOTB_TOPLEVEL=systolic_4x4 SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_systolic VERILOG_SOURCES="$(SYS4_SRCS)"

sim_array8:
	$(MAKE) sim COCOTB_TOPLEVEL=systolic_8x8 SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_systolic VERILOG_SOURCES="$(SYS8_SRCS)"

# Verilator C++ TB (交叉验证 mac)
.PHONY: sim_mac_v
sim_mac_v:
	verilator --cc --exe --trace --top-module mac \
	  -Mdir obj_dir -o sim_mac_v $(MAC_SRCS) $(TB)/tb_mac.cpp
	$(MAKE) -C obj_dir -f Vmac.mk sim_mac_v
	./obj_dir/sim_mac_v

sim_pe:
	$(MAKE) sim COCOTB_TOPLEVEL=pe SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_pe VERILOG_SOURCES="$(PE_SRCS)"

sim_pe16:
	$(MAKE) sim COCOTB_TOPLEVEL=pe_16_64 SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_pe VERILOG_SOURCES="$(PE_SRCS) $(TB)/pe_16_64.sv"

sim_skew:
	$(MAKE) sim COCOTB_TOPLEVEL=skew_systolic_4x4 SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_skew \
	  VERILOG_SOURCES="$(RTL)/input_skew.sv $(SYS4_SRCS) $(TB)/skew_systolic_4x4.sv"

sim_controller:
	$(MAKE) sim COCOTB_TOPLEVEL=controller SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_controller VERILOG_SOURCES="$(RTL)/controller.sv"

sim_top:
	$(MAKE) sim COCOTB_TOPLEVEL=npu_top SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_top \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv"

# regress: 依次跑全部仿真, 每次输出独立日志
# 注: 不能命名为 regression —— cocotb Makefile.inc 中 sim 依赖同名目标, 会互相覆盖
.PHONY: regress
regress:
	@mkdir -p $(LOGDIR)
	@GITREV=$$(git rev-parse --short HEAD); \
	for t in $(REGRESSION_TESTS); do \
	  echo "===== $$t (rev $$GITREV) ====="; \
	  { echo "# regression $$t"; \
	    echo "# git rev: $$(git rev-parse HEAD)"; \
	    echo "# cmd: $(MAKE) $$t"; \
	    echo "# date: $$(date -Iseconds)"; } > $(LOGDIR)/$$t.log; \
	  $(MAKE) $$t >> $(LOGDIR)/$$t.log 2>&1 \
	    || { echo "REGRESSION FAIL at $$t (log: $(LOGDIR)/$$t.log)"; exit 1; }; \
	done
	@echo "REGRESSION PASS"

.PHONY: lint
lint:
	verilator --lint-only -Wall -Wno-fatal -Wno-MULTITOP $(RTL)/*.sv $(TB)/pe_16_64.sv $(TB)/skew_systolic_4x4.sv

.PHONY: synth
synth:
	@command -v yosys >/dev/null 2>&1 || { \
	  echo "yosys not installed (W9 任务, 见 docs/05_ppa_sta_report.md)"; exit 1; }
	@echo "TODO: yosys flow 脚本 (synthesis/flow/)"

.PHONY: mrproper
mrproper:
	rm -rf __pycache__ $(TB)/__pycache__ verification/__pycache__ sim_build results.xml obj_dir
	rm -f *.vcd
	rm -rf $(LOGDIR)

include $(shell cocotb-config --makefiles)/Makefile.sim
