#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
export RTL_SRCS="$REPO/rtl/controller.sv $REPO/rtl/pe_opt2.sv $REPO/synthesis/flow/synth_view/input_skew_sv.sv $REPO/synthesis/flow/synth_view/systolic_array_opt2_sv.sv $REPO/synthesis/flow/synth_view/npu_top_opt2_sv.sv"
bash "$REPO/synthesis/flow/run_synth.sh" "${1:-npu_top_opt2_sv}" "${2:-10.0}"
