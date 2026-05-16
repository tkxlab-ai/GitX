#!/bin/bash
# test_suite_structure.sh — TDD test for S1-6: test suite must exist and be self-contained
# RED: tests/ directory is missing run_all.sh, test_sanitize.sh, test_changelog_gate.sh,
#      test_dual_source.sh and fixtures/
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TESTS_DIR="$SCRIPT_DIR"
PASS=0
FAIL=0

ok() { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_suite_structure.sh ══"

# --- Test 1: run_all.sh exists and is executable ---
if [ -x "$TESTS_DIR/run_all.sh" ]; then
    ok "run_all.sh exists and is executable"
else
    fail "run_all.sh MISSING or not executable (S1-6 not yet implemented)"
fi

# --- Test 2: test_sanitize.sh exists ---
if [ -f "$TESTS_DIR/test_sanitize.sh" ]; then
    ok "test_sanitize.sh exists"
else
    fail "test_sanitize.sh MISSING"
fi

# --- Test 3: test_changelog_gate.sh exists ---
if [ -f "$TESTS_DIR/test_changelog_gate.sh" ]; then
    ok "test_changelog_gate.sh exists"
else
    fail "test_changelog_gate.sh MISSING"
fi

# --- Test 4: test_dual_source.sh exists ---
if [ -f "$TESTS_DIR/test_dual_source.sh" ]; then
    ok "test_dual_source.sh exists"
else
    fail "test_dual_source.sh MISSING"
fi

# --- Test 5: fixtures/ directory exists ---
if [ -d "$TESTS_DIR/fixtures" ]; then
    ok "fixtures/ directory exists"
else
    fail "fixtures/ directory MISSING"
fi

# --- Test 6: run_all.sh actually runs sub-tests and exits 0 ---
if [ -x "$TESTS_DIR/run_all.sh" ]; then
    if bash "$TESTS_DIR/run_all.sh" > /dev/null 2>&1; then
        ok "run_all.sh exits 0 (all tests pass)"
    else
        fail "run_all.sh exits non-0 (some tests failing)"
    fi
else
    fail "run_all.sh not executable — cannot verify it passes"
fi

# --- Summary ---
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
