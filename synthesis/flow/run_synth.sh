#!/usr/bin/env bash
# synthesis/flow/run_synth.sh : 一键综合 + STA (sky130, yosys -> OpenSTA)
# 用法: ./run_synth.sh [DESIGN=npu_top_sv] [CLK_NS=10.0]
# 环境可覆盖: CONDA_BASE (默认 $HOME/miniconda3), PDK_DIR (默认 <CONDA_BASE>/envs/synth/share/pdk/...)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DESIGN="${1:-npu_top_sv}"
CLK_NS="${2:-10.0}"
CLK_PS="$(awk "BEGIN{print int($CLK_NS*1000)}")"

CONDA_BASE="${CONDA_BASE:-$HOME/miniconda3}"
PDK_DIR="${PDK_DIR:-$CONDA_BASE/envs/synth/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd}"
LIB="$PDK_DIR/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
TECHLEF="$PDK_DIR/techlef/sky130_fd_sc_hd__nom.tlef"
CELLLEF="$PDK_DIR/lef/sky130_fd_sc_hd.lef"
FLOW="$REPO/synthesis/flow"
SDC="$REPO/synthesis/constraints.sdc"

source "$CONDA_BASE/etc/profile.d/conda.sh"
conda activate synth

cd "$FLOW"
echo "=== yosys 综合: $DESIGN @ ${CLK_NS}ns (tt_025C_1v80) ==="
REPO="$REPO" DESIGN="$DESIGN" LIB="$LIB" CLK_PS="$CLK_PS" yosys -c synth.tcl \
  | tee "$REPO/synthesis/reports/${DESIGN}_yosys.log"

echo "=== OpenSTA 时序分析 ==="
LIB="$LIB" TECHLEF="$TECHLEF" CELLLEF="$CELLLEF" SDC="$SDC" \
  NETLIST="$REPO/synthesis/reports/${DESIGN}_netlist.v" CLK_NS="$CLK_NS" \
  openroad -no_init -exit sta.tcl 2>&1 \
  | tee "$REPO/synthesis/reports/${DESIGN}_sta_full.rpt"

echo "=== 报告已生成: synthesis/reports/ ==="
ls -la "$REPO/synthesis/reports/${DESIGN}"*
