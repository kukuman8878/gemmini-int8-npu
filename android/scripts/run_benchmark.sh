#!/usr/bin/env bash
# run_benchmark.sh : 小米10 端侧 INT8 推理 benchmark (W13 §3.2)
# 用法: bash android/scripts/run_benchmark.sh [BENCHMARK_MODEL_BIN] [SERIAL]
#   默认 BENCHMARK_MODEL_BIN=android/bin/benchmark_model (需先获取, 见 android/README.md)
set -euo pipefail
cd "$(dirname "$0")/../.."

BIN="${1:-android/bin/benchmark_model}"
SERIAL="${2:-}"
ADB="adb"
[ -n "$SERIAL" ] && ADB="adb -s $SERIAL"

MODEL="android/models/mobilenet_v2_1.0_224_quant.tflite"
DEV_TMP="/data/local/tmp"
DEV_MODEL="$DEV_TMP/mobilenet_v2_1.0_224_quant.tflite"
DEV_BIN="$DEV_TMP/benchmark_model"
OUTDIR="reports/mobile"
mkdir -p "$OUTDIR"

WARMUP=10
RUNS=50
GROUPS=3

echo "=== 检查设备 ==="
$ADB devices
echo "=== 检查 benchmark_model 二进制 ==="
[ -f "$BIN" ] || { echo "缺少 $BIN，请先获取 (见 android/README.md 方案 A)"; exit 1; }

echo "=== push 模型与工具 ==="
$ADB push "$MODEL" "$DEV_MODEL" > /dev/null
$ADB push "$BIN" "$DEV_BIN" > /dev/null
$ADB shell chmod 755 "$DEV_BIN"

STAMP=$(date +%Y%m%d_%H%M%S)
for g in $(seq 1 $GROUPS); do
  echo "=== 第 $g/$GROUPS 组: warmup=$WARMUP runs=$RUNS ==="
  out="$OUTDIR/benchmark_${STAMP}_group${g}.log"
  $ADB shell "$DEV_BIN" \
    --graph="$DEV_MODEL" \
    --num_threads=4 \
    --warmup_runs=$WARMUP \
    --num_runs=$RUNS \
    > "$out" 2>&1
  echo "原始输出: $out"
  grep -iE "average inference|inference \(avg\)|init|warmup|first inference|overall" "$out" | head -8 || true
done

echo "=== 汇总 (见 reports/mobile/) ==="
python3 - "$OUTDIR" "$STAMP" << 'EOF'
import sys, re, glob, statistics, json
outdir, stamp = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(f"{outdir}/benchmark_{stamp}_group*.log"))
rows = []
for f in files:
    txt = open(f, errors="ignore").read()
    # 提取 Inference (avg) us；兼容多种格式
    m = re.search(r"Inference \(avg\)\s*[:=]?\s*([0-9.]+)", txt) or \
        re.search(r"[Ii]nference[^0-9]*([0-9.]+)\s*us", txt)
    rows.append(float(m.group(1)) if m else None)
vals = [r for r in rows if r is not None]
if vals:
    summary = {
        "groups": len(vals), "mean_us": statistics.mean(vals),
        "median_us": statistics.median(vals),
        "p90_us": sorted(vals)[int(len(vals)*0.9)] if len(vals) >= 3 else max(vals),
        "per_group_us": vals,
    }
    json.dump(summary, open(f"{outdir}/benchmark_{stamp}_summary.json", "w"), indent=2)
    print(json.dumps(summary, indent=2, ensure_ascii=False))
else:
    print("未解析到延迟数字，请检查 benchmark_model 输出格式 (见原始 .log)")
EOF
