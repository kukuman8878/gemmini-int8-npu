# synthesis/flow/synth.tcl : yosys 综合 + 面积 + STA 报告
# 用法: DESIGN=... LIB=... CLK_PS=... yosys -c synth.tcl (tclsh + yosys import)
yosys -import

set design  $env(DESIGN)
set lib     $env(LIB)
set clk_ps  $env(CLK_PS)
set srcs    $env(RTL_SRCS)

read_liberty -lib $lib

read_verilog -sv {*}$srcs

hierarchy -top $design

# 注: 在 tclsh 模式下 proc 是 TCL 内置命令, 需用 yosys proc 前缀调用
yosys proc
opt
fsm
memory
opt
techmap
opt
dfflibmap -liberty $lib
abc -liberty $lib -D 4000

# 扁平化后统计顶层总面积 (层次化 stat 无法累加 16x PE 实例)
flatten
opt_clean

# 面积与门数报告
tee -o $env(REPO)/synthesis/reports/${design}_stat.rpt stat -liberty $lib

# 时序分析由 OpenSTA 完成 (synthesis/flow/sta.tcl), yosys 内置 sta 为玩具版不使用
write_verilog -noattr $env(REPO)/synthesis/reports/${design}_netlist.v
