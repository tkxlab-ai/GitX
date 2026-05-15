#!/bin/bash
# test_audit_kb_hardcode.sh — S3-6
# §10 must FAIL (not silently warn) when RELEASE_NOTES contains hardcoded KB numbers.
# exit: 0=pass, 1=fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT_SH="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_kb_hardcode.sh ══"

# Extract §10 block
section=$(awk '/^echo "§10\./{flag=1} flag; /^echo "§11\./{flag=0}' "$AUDIT_SH")

# ── Test 1: KB-hardcode branch increments FAIL (not just ⚠️) ──────────────
kb_branch=$(echo "$section" | awk '/grep -qE .\[0-9\]\+ KB/{flag=1; next} flag && /else/{flag=0} flag')
if echo "$kb_branch" | grep -q 'FAIL=\$((FAIL+1))'; then
    ok "§10 KB-hardcode branch increments FAIL (S3-6)"
else
    fail "§10 KB-hardcode branch does NOT increment FAIL (S3-6: always-green warn)"
fi

# ── Test 2: uses ❌ marker, not just ⚠️ ────────────────────────────────────
if echo "$kb_branch" | grep -q '❌'; then
    ok "§10 KB-hardcode branch uses ❌ marker"
else
    fail "§10 KB-hardcode branch uses soft ⚠️ only (S3-6: should be hard fail)"
fi

# ── Test 3: title no longer says 软警告 ────────────────────────────────────
if echo "$section" | head -1 | grep -q '软警告'; then
    fail "§10 title still says 软警告 — S3-6 requires hard gate"
else
    ok "§10 title is hard-gate (no '软警告')"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
