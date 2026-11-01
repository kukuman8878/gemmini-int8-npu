#!/usr/bin/env bash
# device_audit.sh : 小米10 设备审计 (W13 §3.2)
# 采集型号/SoC/Android版本/ABI/存储/内存/电量/温度, 写入 android/device_manifest.json
# 用法: bash android/scripts/device_audit.sh [serial]
set -euo pipefail
cd "$(dirname "$0")/../.."

ADB="adb"
if [ $# -ge 1 ]; then ADB="adb -s $1"; fi

echo "=== 检查设备 ==="
$ADB devices -l

echo "=== 采集设备信息 ==="
model=$($ADB shell getprop ro.product.model | tr -d '\r')
manuf=$($ADB shell getprop ro.product.manufacturer | tr -d '\r')
soc=$($ADB shell getprop ro.board.platform | tr -d '\r')
android=$($ADB shell getprop ro.build.version.release | tr -d '\r')
api=$($ADB shell getprop ro.build.version.sdk | tr -d '\r')
abi=$($ADB shell getprop ro.product.cpu.abi | tr -d '\r')
storage_total=$($ADB shell df /data | tail -1 | awk '{print $2}')
storage_free=$($ADB shell df /data | tail -1 | awk '{print $4}')
mem_total=$($ADB shell cat /proc/meminfo | grep MemTotal | awk '{print $2}')
battery=$($ADB shell dumpsys battery | grep "level:" | awk '{print $2}')
temp=$($ADB shell cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | tr -d '\r')

echo "model=$model manuf=$manuf soc=$soc android=$android api=$api abi=$abi"
echo "storage_total=${storage_total}KB storage_free=${storage_free}KB mem_total=${mem_total}KB"
echo "battery=${battery} temp=${temp}"

# 用 python 写回 manifest (字段类型化)
python3 - "$model" "$manuf" "$soc" "$android" "$api" "$abi" \
  "$storage_total" "$storage_free" "$mem_total" "$battery" "$temp" << 'EOF'
import json, sys
(m, mf, soc, android, api, abi, st, sf, mem, bat, tmp) = sys.argv[1:]
p = "android/device_manifest.json"
d = json.load(open(p))
d["device"].update({
    "model": m, "manufacturer": mf, "soc": soc, "android_version": android,
    "api_level": api, "abi": abi,
    "storage_total_gb": round(int(st)/1024/1024, 2) if st.isdigit() else "",
    "storage_free_gb": round(int(sf)/1024/1024, 2) if sf.isdigit() else "",
    "memory_total_gb": round(int(mem)/1024/1024, 2) if mem.isdigit() else "",
    "battery_level_pct": int(bat) if bat.isdigit() else "",
    "temperature_celsius": (int(tmp)/1000) if tmp and tmp.lstrip('-').isdigit() else "",
    "usb_debug": True,
})
d["audit"].update({"date": __import__("datetime").datetime.now().isoformat()})
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
print("written android/device_manifest.json")
EOF
