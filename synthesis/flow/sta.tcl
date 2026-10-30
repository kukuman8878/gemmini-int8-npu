# synthesis/flow/sta.tcl : OpenSTA (via openroad) 静态时序分析
# 用法: LIB=... TECHLEF=... CELLLEF=... NETLIST=... CLK_NS=... SDC=... openroad -no_init -exit sta.tcl
# 口径: 读 yosys 映射后网表 + sky130 liberty/LEF; 约束消费 synthesis/constraints.sdc
read_lef $::env(TECHLEF)
read_lef $::env(CELLLEF)
read_liberty $::env(LIB)
read_verilog $::env(NETLIST)
link_design $::env(DESIGN)

# 时钟周期从环境变量读取 (SDC 内 $env(CLK_NS)); 未设置时默认 10.0ns
if {![info exists ::env(CLK_NS)]} { set ::env(CLK_NS) 10.0 }
read_sdc $::env(SDC)

report_checks -path_delay max -format full_clock_expanded
report_worst_slack -max
