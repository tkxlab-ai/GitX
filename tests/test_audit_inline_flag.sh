#!/bin/bash
# test_audit_inline_flag.sh — v0.9.7
# release-audit.sh must accept `--inline` (passed by release.sh) and relax §8
# when latest points to a DIFFERENT existing release (N+1 scenario: latest
# still points to vN while we're mid-release of vN+1). Standalone audit
# retains strict semantics — if latest is wrong, it's a real problem.
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
RELEASE="$SCRIPT_DIR/../scripts/release.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_inline_flag.sh ══"

# ── Test 1: release-audit.sh parses --inline flag ──────────────────────────
if grep -qE -- '--inline|"--inline"|INLINE=' "$AUDIT"; then
    ok "release-audit.sh recognises --inline flag"
else
    fail "release-audit.sh does NOT parse --inline flag"
fi

# ── Test 2: §8 mismatched-target branch checks INLINE mode ─────────────────
# When INLINE=1 AND latest_target dir exists, branch should SKIP, not FAIL.
block=$(awk '/^# --- §8 Release\/latest/,/^# --- §9/' "$AUDIT")
if echo "$block" | grep -qE 'INLINE.*[0-9]|INLINE.*==.*"1"|\$\{INLINE:?-?[0-9]*\}'; then
    ok "§8 branch references INLINE variable"
else
    fail "§8 does NOT reference INLINE (still strict in all modes)"
fi

# ── Test 3: standalone mode (INLINE=0) must keep strict check ──────────────
# There must still be a FAIL=$((FAIL+1)) path inside §8's mismatched-target
# branch so that post-release standalone audit catches wrong latest.
if echo "$block" | grep -q 'FAIL=\$((FAIL+1))'; then
    ok "§8 still has FAIL path for standalone wrong-target"
else
    fail "§8 lost FAIL path entirely — standalone would not catch wrong latest"
fi

# ── Test 4: release.sh passes --inline when invoking audit ────────────────
if grep -qE 'bash .*release-audit.sh.*--inline|"\$AUDIT".*--inline|AUDIT.*--inline' "$RELEASE"; then
    ok "release.sh passes --inline to release-audit.sh"
else
    fail "release.sh does NOT pass --inline when invoking audit"
fi

# ── Test 5: functional — --inline is consumed without eating $VERSION ─────
# Passing `--inline <ver>` or `<ver> --inline` must leave VERSION set.
# We probe by invoking audit with a nonexistent project — it will fail on
# PROJECT_ROOT check, but if argv parsing is broken we would instead see
# the "Usage:" error (meaning VERSION was empty because --inline consumed it).
usage_err=$(bash "$AUDIT" --inline v99.99.99 2>&1 | head -3 || true)
if echo "$usage_err" | grep -qE 'Usage:'; then
    fail "audit --inline before version causes usage error (argv parsing broken)"
else
    ok "audit --inline v<ver> parses argv correctly"
fi

usage_err2=$(bash "$AUDIT" v99.99.99 --inline 2>&1 | head -3 || true)
if echo "$usage_err2" | grep -qE 'Usage:'; then
    fail "audit v<ver> --inline causes usage error (argv parsing broken)"
else
    ok "audit v<ver> --inline parses argv correctly"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
