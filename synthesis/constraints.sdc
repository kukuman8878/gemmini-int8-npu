# SDC 约束 (sky130_fd_sc_hd, tt_025C_1v80; OpenSTA 执行口径见 docs/05)
# 公平比较规则: baseline 与 optimized 必须使用同一份约束
# 注: OpenSTA SDC 不支持 remove_from_collection, 故显式列出数据端口;
#     排除 clk/rst_n 且不含调试输出 state (不对其约束时序)

create_clock -name clk -period 10.0 [get_ports clk]

set_input_delay  -clock clk 2.0 [get_ports {a_vec_flat b_vec_flat cfg_k start in_valid cfg_valid out_ready}]
set_output_delay -clock clk 2.0 [get_ports {out_c_flat out_valid busy done cfg_ready in_ready}]
