#!/bin/bash
# test_audit_dual_source_required.sh — S3-4
# Policy v2.3: when dual-source layout is missing, audit §9 must FAIL (not SKIP).
# exit: 0=pass, 1=fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_SH="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_dual_source_required.sh ══"

# ── Test 1: §9 section exists ──────────────────────────────────────────────
if grep -q '§9. 双源脚本一致性' "$AUDIT_SH"; then
    ok "§9 section present in release-audit.sh"
else
    fail "§9 section MISSING — cannot verify policy"
    exit 1
fi

# ── Test 2: §9 missing-dual-source branch marks FAIL, not SKIP ──────────────
# Extract the §9 block (between its header and next '§' header or EOF)
section=$(awk '/^echo "§9\./{flag=1} flag; /^echo "§10\./{flag=0}' "$AUDIT_SH")

# The else branch (no dual source) must increment FAIL; must not increment SKIP
else_branch=$(echo "$section" | awk '/^else$/{flag=1} flag; /^fi$/{flag=0}')

if echo "$else_branch" | grep -q 'FAIL=\$((FAIL+1))'; then
    ok "§9 else branch increments FAIL on missing dual-source (S3-4)"
else
    fail "§9 else branch does NOT increment FAIL (S3-4: should not SKIP)"
fi

if echo "$else_branch" | grep -q 'SKIP=\$((SKIP+1))'; then
    fail "§9 else branch still increments SKIP — policy violation (S3-4)"
else
    ok "§9 else branch does NOT increment SKIP"
fi

# ── Test 3: else branch emits ❌ message, not ➖ ────────────────────────────
if echo "$else_branch" | grep -q '❌'; then
    ok "§9 else branch emits ❌ error marker"
else
    fail "§9 else branch missing ❌ marker (S3-4: should signal failure clearly)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
