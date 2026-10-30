#!/usr/bin/env bash
# 综合 optimized 变体 (CSA 阵列 + 输出寄存器)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
export RTL_SRCS="$REPO/rtl/controller.sv $REPO/rtl/pe_opt.sv $REPO/synthesis/flow/synth_view/input_skew_sv.sv $REPO/synthesis/flow/synth_view/systolic_array_opt_sv.sv $REPO/synthesis/flow/synth_view/npu_top_opt_sv.sv"
bash "$REPO/synthesis/flow/run_synth.sh" "${1:-npu_top_opt_sv}" "${2:-10.0}"
