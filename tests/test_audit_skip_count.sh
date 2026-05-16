#!/bin/bash
# test_audit_skip_count.sh — TDD test for S1-3: SKIP counter + three-state Summary
# RED: expects SKIP variable and three-state output in release-audit.sh
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/release-audit.sh"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_audit_skip_count.sh ══"

# --- Test 1: SKIP=0 initialisation exists ---
# audit script must declare SKIP=0 near FAIL=0/PASS=0
if grep -q "^SKIP=0" "$AUDIT"; then
    ok "SKIP=0 initialisation found"
else
    fail "SKIP=0 initialisation MISSING — S1-3 not yet implemented"
fi

# --- Test 2: TOTAL includes SKIP ---
# TOTAL=$((PASS + FAIL + SKIP))
if grep -qE 'TOTAL=\$\(\(PASS \+ FAIL \+ SKIP\)\)' "$AUDIT"; then
    ok "TOTAL includes SKIP in formula"
else
    fail "TOTAL formula does not include SKIP — still PASS+FAIL only"
fi

# --- Test 3: three-state summary format in PASS branch ---
# Must contain ✅$PASS / ❌$FAIL / ➖$SKIP pattern
if grep -q '✅\$PASS' "$AUDIT" && grep -q '❌\$FAIL' "$AUDIT" && grep -q '➖\$SKIP' "$AUDIT"; then
    ok "Three-state summary format present (✅/❌/➖)"
else
    fail "Three-state summary format MISSING — only two-state output found"
fi

# --- Test 4: existing ➖ branches increment SKIP ---
# line 153: "  ➖ $f 缺失，跳过 diff" must be followed by SKIP increment
# We check that at least one SKIP increment exists in the file
if grep -q 'SKIP=\$((SKIP+1))' "$AUDIT"; then
    ok "SKIP increment found in at least one ➖ branch"
else
    fail "No SKIP=\$((SKIP+1)) found — ➖ branches not counting skips"
fi

# --- Test 5 (S2-5): warn() function exists and §2b/§6b uses warn() not check() ---
# §2b doc-quality checks (grep -qiE install/安装) should be warn(), not check()
if grep -q "^warn()" "$AUDIT"; then
    ok "warn() function defined in release-audit.sh"
else
    fail "warn() function MISSING (S2-5: §2b/§6b soft-warn not yet implemented)"
fi

# §2b 안装/install 검사가 warn() 호출인지 확인 (check() 로 남아있으면 FAIL)
if grep -qE 'warn.*install|warn.*安装' "$AUDIT"; then
    ok "§2b/§6b install/安装 checks use warn() (soft warning)"
else
    fail "§2b/§6b install/安装 checks still use check() — S2-5 not implemented"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
