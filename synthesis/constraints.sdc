# SDC 约束 (sky130_fd_sc_hd, tt_025C_1v80; OpenSTA 执行口径见 docs/05)
# 公平比较规则: baseline 与 optimized 必须使用同一份约束

create_clock -name clk -period 10.0 [get_ports clk]
set_input_delay  -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]
