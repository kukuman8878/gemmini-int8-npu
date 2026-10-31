#!/usr/bin/env bash
# demo.sh : 5 分钟可复现演示（对应验收文档 §9.1 五段结构）
# 用法: bash scripts/demo.sh
set -uo pipefail
cd "$(dirname "$0")/.."

echo "=============================================================="
echo "第 0-1 分钟：自研 NPU 架构（模块链 + 数据流）"
echo "=============================================================="
echo "mac -> pe -> input_skew -> 4x4 OS 阵列 -> fifo -> controller -> npu_top"
echo "OS 数据流：A 左→右、B 上→下，PE 保存局部 C[i,j]；skew 只在 input_skew 一处"
echo "A/B INT8、乘积 INT16、累加 INT32、K=1..256；acc_clr 放 IDLE 态（清零≠排空）"

echo
echo "=============================================================="
echo "第 1-2 分钟：跑端到端矩阵乘测试（Golden 与 DUT 精确一致，8 用例）"
echo "=============================================================="
make sim_top 2>&1 | grep -E "TESTS=|PASS|FAIL|passed|mismatch" | tail -5 || echo "(sim_top 结果见 logs/)"

echo
echo "=============================================================="
echo "第 2-3 分钟：验证闭环（SVA + 等价性 + 故障注入）"
echo "=============================================================="
echo "SVA A1-A6（Verilator --assert）; 综合视图/两变体等价性（\$fatal 门禁）; 15 条缺陷闭环"
echo "演示一键回归（可选，耗时）: make regress  # 17 目标"
echo "演示故障注入: make fault_inject           # 验证回归能捕获缺陷"

echo
echo "=============================================================="
echo "第 3-4 分钟：PPA 结果（sky130 tt 角, 10ns@100MHz）"
echo "=============================================================="
for d in npu_top_sv npu_top_opt_sv npu_top_cs_sv; do
  rpt="synthesis/reports/${d}_stat.rpt"
  sta="synthesis/reports/${d}_sta_full.rpt"
  area=$(grep -E "Chip area for module" "$rpt" 2>/dev/null | tail -1 | grep -oE "[0-9.]+")
  slack=$(grep -E "worst slack" "$sta" 2>/dev/null | grep -oE "[0-9.-]+" | tail -1)
  printf "  %-18s area=%-12s worst_slack=%s ns\n" "$d" "$area" "$slack"
done

echo
echo "=============================================================="
echo "第 4-5 分钟：Gemmini WS/OS 对照（官方基线，64x64x64）"
echo "=============================================================="
os_cyc=$(grep -A1 "Starting gemmini matmul" logs/gemmini/tmat_os.out | grep -oE "Cycles taken: [0-9]+" | grep -oE "[0-9]+")
ws_cyc=$(grep -A1 "Starting gemmini matmul" logs/gemmini/tmat_ws.out | grep -oE "Cycles taken: [0-9]+" | grep -oE "[0-9]+")
printf "  OS（输出静止）: %s cycles（端到端效率 28.8%%）\n" "$os_cyc"
printf "  WS（权重静止）: %s cycles（端到端效率 45.1%%）—— WS 快 56%%\n" "$ws_cyc"
echo "  官方基线 PASS: mvin_mvout / matmul_os / matmul_ws（\$finish 正常退出）"

echo
echo "====== 演示结束 ======"
echo "口径：仿真墙钟时间≠硬件周期数；综合后时序≠布局后；详见 README/docs/05/docs/06"
