# gemmini-int8-npu Makefile
# 目标: lint / sim_mac / sim_mac_v / sim_pe / sim_pe16 / sim_skew / sim_fifo / sim_array / sim_array8 / regress / synth / mrproper

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

RTL ?= rtl
TB := tb

SEED ?= 2024       # 随机回归种子 (sim_top_seeded)
PAIRS ?= 20        # 每种 K 的随机 tile 对数 (sim_top_seeded)

MAC_SRCS  := $(RTL)/mac.sv
FIFO_SRCS := $(RTL)/fifo.sv
PE_SRCS   := $(RTL)/pe.sv
SYS4_SRCS := $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/systolic_4x4.sv
SYS8_SRCS := $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/systolic_8x8.sv

LOGDIR := logs
REGRESSION_TESTS := sim_mac sim_mac_v sim_pe sim_pe16 sim_pe_sva sim_skew sim_controller sim_top sim_top_sva sim_equiv sim_equiv_opt sim_equiv_cs sim_fifo sim_fifo_sva sim_array sim_array8 sim_bench

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

# SVA 断言目标 (Verilator --assert 后端; icarus 不支持并发 SVA)
.PHONY: sim_top_sva sim_pe_sva sim_fifo_sva

sim_top_sva:
	$(MAKE) sim SIM=verilator COCOTB_TOPLEVEL=npu_top_assert SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_top EXTRA_ARGS="--assert" \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv $(TB)/npu_top_assert.sv"

sim_pe_sva:
	$(MAKE) sim SIM=verilator COCOTB_TOPLEVEL=pe_assert SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_pe EXTRA_ARGS="--assert" \
	  VERILOG_SOURCES="$(RTL)/pe.sv $(TB)/pe_assert.sv"

sim_fifo_sva:
	$(MAKE) sim SIM=verilator COCOTB_TOPLEVEL=fifo_assert SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_fifo EXTRA_ARGS="--assert" \
	  VERILOG_SOURCES="$(RTL)/fifo.sv $(TB)/fifo_assert.sv"

# 综合视图等价性验证 (原 RTL vs 打包端口综合视图, 逐拍比对)
sim_equiv:
	$(MAKE) sim COCOTB_TOPLEVEL=equiv_wrap SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_top \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv synthesis/flow/synth_view/input_skew_sv.sv synthesis/flow/synth_view/systolic_array_sv.sv synthesis/flow/synth_view/npu_top_sv.sv $(TB)/equiv_wrap.sv"

# optimized 变体等价性验证 (baseline npu_top vs CSA npu_top_opt, 结果值比对)
sim_equiv_opt:
	$(MAKE) sim COCOTB_TOPLEVEL=equiv_opt_wrap SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_top \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv $(RTL)/pe_opt.sv $(RTL)/systolic_array_opt.sv $(RTL)/npu_top_opt.sv $(TB)/equiv_opt_wrap.sv"

# carry-select 变体等价性验证 (baseline npu_top vs npu_top_cs, 逐拍比对)
sim_equiv_cs:
	$(MAKE) sim COCOTB_TOPLEVEL=equiv_cs_wrap SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_top \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv $(RTL)/pe_cs.sv $(RTL)/systolic_array_cs.sv $(RTL)/npu_top_cs.sv $(TB)/equiv_cs_wrap.sv"

# 周期测量基准 (W10): 断言 load/drain/output 分量与 controller 语义一致
sim_bench:
	$(MAKE) sim COCOTB_TOPLEVEL=npu_top SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_bench \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv"

# W14 真实 1×1 Conv→GEMM 的 RTL 一致性验证 (TILES 环境变量控制 tile 数)
sim_phone_layer:
	TILES=$(TILES) $(MAKE) sim COCOTB_TOPLEVEL=npu_top SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_phone_layer \
	  VERILOG_SOURCES="$(RTL)/controller.sv $(RTL)/input_skew.sv $(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/npu_top.sv"

# 批量随机回归入口 (SEED/PAIRS 由环境传入, 见 verification/random_regression.py)
sim_top_seeded:
	SEED=$(SEED) PAIRS=$(PAIRS) $(MAKE) sim COCOTB_TOPLEVEL=npu_top SIM_BUILD=sim_build/$@ \
	  COCOTB_RESULTS_FILE=sim_build/$@/results.xml \
	  COCOTB_TEST_MODULES=tb_regression \
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
	verilator --lint-only -Wall -Wno-fatal -Wno-MULTITOP -Wno-SYNCASYNCNET \
	  $(RTL)/*.sv $(TB)/pe_16_64.sv $(TB)/skew_systolic_4x4.sv \
	  $(TB)/npu_top_assert.sv $(TB)/pe_assert.sv $(TB)/fifo_assert.sv \
	  $(TB)/equiv_wrap.sv $(TB)/equiv_opt_wrap.sv $(TB)/equiv_cs_wrap.sv \
	  synthesis/flow/synth_view/input_skew_sv.sv \
	  synthesis/flow/synth_view/systolic_array_sv.sv \
	  synthesis/flow/synth_view/systolic_array_opt_sv.sv \
	  synthesis/flow/synth_view/systolic_array_cs_sv.sv \
	  synthesis/flow/synth_view/npu_top_sv.sv \
	  synthesis/flow/synth_view/npu_top_opt_sv.sv \
	  synthesis/flow/synth_view/npu_top_cs_sv.sv

# V12 故障注入 (脚本用 RTL= 覆盖在 /tmp 变异副本上运行, 独立 SIM_BUILD 不污染正常回归)
.PHONY: fault_inject sim_array_fault
fault_inject:
	bash scripts/fault_injection.sh

sim_array_fault:
	$(MAKE) sim COCOTB_TOPLEVEL=systolic_4x4 SIM_BUILD=sim_build/fault_inject \
	  COCOTB_RESULTS_FILE=sim_build/fault_inject/results.xml \
	  COCOTB_TEST_MODULES=tb_systolic \
	  VERILOG_SOURCES="$(RTL)/pe.sv $(RTL)/systolic_array.sv $(RTL)/systolic_4x4.sv"

.PHONY: synth
synth:
	bash synthesis/flow/run_synth.sh $(DESIGN) $(CLK_NS)

.PHONY: mrproper
mrproper:
	rm -rf __pycache__ $(TB)/__pycache__ verification/__pycache__ sim_build results.xml obj_dir
	rm -f *.vcd
	rm -rf $(LOGDIR)

include $(shell cocotb-config --makefiles)/Makefile.sim
