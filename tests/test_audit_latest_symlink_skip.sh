#!/bin/bash
# test_audit_latest_symlink_skip.sh — v0.9.6
# When release.sh runs audit inline BEFORE creating Release/latest (S1-5 order),
# audit §8 must not hard-FAIL on "latest missing". Treat absence as ➖ SKIP.
# A mismatched target (points to wrong version) is still ❌ FAIL.
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_latest_symlink_skip.sh ══"

# ── Test 1: absent-latest branch uses SKIP, not FAIL ──────────────────────
# Extract the §8 block (next ~15 lines after `§8. Release/latest`)
block=$(awk '/^# --- §8 Release\/latest/,/^# --- §9/' "$AUDIT")

if [ -z "$block" ]; then
    fail "could not locate §8 block in audit script"
    echo "Results: ✅$PASS passed / ❌$FAIL failed"
    exit 1
fi

# Find the else-branch (absent) handler
absent_branch=$(echo "$block" | awk '/^else/,/^fi/')

if echo "$absent_branch" | grep -q 'SKIP=\$((SKIP+1))'; then
    ok "§8 absent-latest increments SKIP"
else
    fail "§8 absent-latest does NOT increment SKIP (still hard-FAIL)"
fi

if echo "$absent_branch" | grep -q 'FAIL=\$((FAIL+1))'; then
    fail "§8 absent-latest STILL increments FAIL (should be SKIP only)"
else
    ok "§8 absent-latest does NOT increment FAIL"
fi

# ── Test 2: absent-latest emits ➖ marker, not ❌ ───────────────────────────
if echo "$absent_branch" | grep -q '➖'; then
    ok "§8 absent-latest uses ➖ SKIP marker"
else
    fail "§8 absent-latest missing ➖ SKIP marker"
fi

# ── Test 3: mismatched-target branch STILL hard-FAILs (invariant preserved) ─
# The inner `if [ "$latest_target" = <expected> ]; ... else ... fi` mismatch
# branch should keep emitting ❌ FAIL — regression guard.
# v0.9.10: the comparison now targets `$EXPECTED_LATEST` (which may be
# `$VERSION` in legacy mode or `${PROJECT_NAME}-${VERSION}` in new mode).
# Match any `latest_target` equality check followed by an `fi` terminator.
mismatch_branch=$(echo "$block" | awk '/latest_target.*=.*(VERSION|EXPECTED_LATEST)/,/^[[:space:]]*fi/' | tail -n +2)

if echo "$mismatch_branch" | grep -q '❌.*latest_target\|Release/latest → \$latest_target'; then
    ok "§8 mismatched-target branch still uses ❌ marker"
else
    fail "§8 mismatched-target branch lost ❌ marker — invariant regression"
fi

if echo "$mismatch_branch" | grep -q 'FAIL=\$((FAIL+1))'; then
    ok "§8 mismatched-target branch still increments FAIL"
else
    fail "§8 mismatched-target branch no longer increments FAIL — invariant regression"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
