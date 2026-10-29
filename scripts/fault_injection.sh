#!/usr/bin/env bash
# scripts/fault_injection.sh : V12 故障注入 (不触碰工作区)
#   在 /tmp 的 RTL 副本上注入已知缺陷, 验证回归能捕获 (期望 FAIL)
#   用法: make fault_inject 或 scripts/fault_injection.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MUT="$(mktemp -d /tmp/fault_inject.XXXXXX)"
trap 'rm -rf "$MUT" "$REPO/sim_build/fault_inject"' EXIT

cp -r "$REPO/rtl" "$MUT/rtl"
# 变异: 破坏 PE en 门控 (en_a&&en_b -> en_a)
sed -i 's/if (en_a && en_b)/if (en_a)/' "$MUT/rtl/pe.sv"
if ! diff -q "$MUT/rtl/pe.sv" "$REPO/rtl/pe.sv" >/dev/null; then
    echo "mutation applied: pe.sv en gating broken"
else
    echo "ERROR: mutation not applied"; exit 1
fi

cd "$REPO"
set +e
make sim_array_fault RTL="$MUT/rtl" > "$MUT/run.log" 2>&1
RC=$?
set -e
if [ $RC -eq 0 ]; then
    echo "FAULT INJECTION: NOT CAUGHT (回归假绿!)"
    exit 1
fi
if grep -qE "MISMATCH|AssertionError|TESTS=.*FAIL=[1-9]" "$MUT/run.log"; then
    echo "FAULT INJECTION CAUGHT ✓ (回归正确失败)"
    grep -E "MISMATCH|TESTS=" "$MUT/run.log" | head -3
    exit 0
fi
echo "FAILED but not by assertion (rc=$RC), see $MUT/run.log"
exit 1
