# synthesis/flow/sta.tcl : OpenSTA (via openroad) 静态时序分析
# 用法: LIB=... TECHLEF=... CELLLEF=... NETLIST=... CLK_NS=... SDC=... openroad -no_init -exit sta.tcl
# 口径: 读 yosys 映射后网表 + sky130 liberty/LEF; 约束消费 synthesis/constraints.sdc
read_lef $::env(TECHLEF)
read_lef $::env(CELLLEF)
read_liberty $::env(LIB)
read_verilog $::env(NETLIST)
link_design npu_top_sv

read_sdc $::env(SDC)

report_checks -path_delay max -format full_clock_expanded
report_worst_slack -max
