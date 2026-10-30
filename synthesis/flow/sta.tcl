# synthesis/flow/sta.tcl : OpenSTA (via openroad) 静态时序分析
# 用法: LIB=... TECHLEF=... CELLLEF=... NETLIST=... CLK_NS=... openroad -no_init -exit sta.tcl
# 口径: 读 yosys 映射后网表 + sky130 liberty/LEF, 单时钟, IO 延迟 2ns
read_lef $::env(TECHLEF)
read_lef $::env(CELLLEF)
read_liberty $::env(LIB)
read_verilog $::env(NETLIST)
link_design npu_top_sv

create_clock -name clk -period $::env(CLK_NS) [get_ports clk]
set_input_delay  -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]

report_checks -path_delay max -format full_clock_expanded
report_worst_slack -max
