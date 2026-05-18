#!/bin/bash
# test_docs_contract.sh — manifest parse + cjk-allow + 5-region inventory
set -euo pipefail

ROOT="${PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
M="$ROOT/references/docs-contract/manifest.txt"
A="$ROOT/references/docs-contract/cjk-allow.txt"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_docs_contract.sh ══"
[ -f "$M" ] && ok "manifest exists" || fail "manifest missing"
[ -f "$A" ] && ok "cjk-allow exists" || fail "cjk-allow missing"
regs=$(grep -E '^region:' "$M" 2>/dev/null | sed 's/^region:[[:space:]]*//' | sort | tr '\n' ' ')
[ "$regs" = "badges build-metrics command-surface suite-count whats-new " ] \
  && ok "5-region inventory exact" || fail "region set wrong: '$regs'"
grep -qE '^h3_threshold:[[:space:]]*8$' "$M" && ok "H3 threshold = 8" || fail "H3 threshold not 8"
grep -qE '^doc:README\.md[[:space:]]+locale:en' "$M" && ok "EN README declared" || fail "EN README missing"
grep -qE '^doc:README_CN\.md[[:space:]]+locale:cn' "$M" && ok "CN README declared" || fail "CN README missing"
for t in GitX shellcheck CHANGELOG projen; do
  grep -qxF "$t" "$A" && ok "cjk-allow has $t" || fail "cjk-allow missing $t"
done
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && { echo "PASS"; exit 0; } || { echo "FAIL"; exit 1; }
