#!/usr/bin/env bash
# final_demo.sh : W16 最终演示 (5-8 分钟, 对应文档 §6.4 六段)
# 用法: bash scripts/final_demo.sh
set -uo pipefail
cd "$(dirname "$0")/.."

say() { echo; echo "=============================================================="; echo "$*"; echo "=============================================================="; }

say "0:00-1:00 真实问题：小米10 上的 INT8 模型如何映射为 NPU 硬件"
echo "  目标：端侧 AI (MobileNetV2 INT8) 在真实设备跑通，并解释其 1×1 卷积如何变成矩阵乘、"
echo "        如何在自研 4×4 脉动阵列与 Gemmini 16×16 仿真上逐元素一致。"
echo "  三套结果红线：手机实测(ms) ≠ RTL 仿真(cycles) ≠ EDA 估计(面积/时序)。"

say "1:00-2:00 手机端实测 (W13)"
echo "  设备: 小米10 (骁龙865/Android13/11.3GB)"
echo "  模型: MobileNetV2 1.0 224 INT8 (SHA-256 f08d447c...)"
echo "  CPU 推理延迟 (benchmark_model, XNNPACK 4线程):"
grep -H "Inference (avg)" reports/mobile/benchmark_*group*.log 2>/dev/null | tail -3 || \
  echo "    9.16 ms (3 组 avg 9.17/9.16/9.16, 各 110 runs)"

say "2:00-3:30 真实 1×1 Conv→GEMM 映射 + 量化对齐 (W14)"
echo "  选定层: pointwise Cin=320→Cout=1280 (K 较大、空间位置充足)"
echo "  GEMM: A[49,320] × B[320,1280] = C[49,1280], K 分块 320=256+64"
echo "  量化契约: uint8 - zero_point(输入130/权重125) → int8 (clamp -128..127)"
echo "  (关键发现: 非对称量化减零点后超 int8, 需 clamp 对齐)"
python3 - << 'EOF'
import json
q = json.load(open("benchmarks/phone_layer_01/quant.json"))
t = json.load(open("benchmarks/phone_layer_01/tiling.json"))
print(f"  M={q['M']} K={q['K']} N={q['N']}, 输入 zp={q['input']['zero_point']} 权重 zp={q['weight']['zero_points'][0]}")
print(f"  切块: M_tiles={t['M_tiles']} N_tiles={t['N_tiles']} K_blocks={t['K_blocks']}")
EOF

say "3:30-5:00 RTL / Gemmini 一致性 (W14)"
echo "  三方一致性 (同一真实层, int8 语义 INT32 累加):"
echo "    Python golden    : 基准"
echo "    自研 4×4 RTL     : 5120 元素 0 mismatch"
echo "    Gemmini 16×16    : 784 元素 0 mismatch (N=16 子集)"

say "5:00-6:30 验证环境 + 覆盖率 + PPA 对照 (W7-W10, W15)"
echo "  验证: 18 个回归目标全绿; 覆盖模型 coverpoint 28/28; SVA A1-A6; 故障注入闭环"
python3 verification/coverage_model.py 2>/dev/null | grep "命中率"
echo "  PPA (sky130 tt 角, 10ns, 同约束):"
for d in npu_top_sv npu_top_opt_sv npu_top_cs_sv npu_top_opt2_sv; do
  area=$(grep -E "Chip area for module" "synthesis/reports/${d}_stat.rpt" 2>/dev/null | tail -1 | sed -E 's/.*: *([0-9.]+).*/\1/')
  slack=$(grep -E "worst slack" "synthesis/reports/${d}_sta_full.rpt" 2>/dev/null | grep -oE "[0-9.-]+" | tail -1)
  printf "    %-20s area=%-12s worst_slack=%s\n" "$d" "$area" "$slack"
done
echo "  结论: CSA 累加环(乘法+压缩)是真正瓶颈(~6-7ns); 输出合并流水化是负收益(已纠正 W10 认知)"

say "6:30-8:00 原创代码 + 局限 + 下一步"
echo "  原创: rtl/ 全部 RTL (mac/pe/skew/阵列/fifo/controller/npu_top + 3 优化变体)"
echo "        tb/ + verification/ (cocotb + Scoreboard + SVA + 覆盖模型 + 故障注入)"
echo "        synthesis/ (yosys+OpenSTA 流程 + PPA 报告)"
echo "  局限: 单 tile 4×4 OS; K≤256 需分块; 无片上存储(数据测试端喂入); 无功耗库"
echo "  下一步: 乘法器流水化(缩短累加环) / 8×8 扩展 / Gemmini Chisel 集成"

echo; echo "====== 演示结束 (口径红线见 docs/10) ======"
