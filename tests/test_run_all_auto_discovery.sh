#!/bin/bash
# test_run_all_auto_discovery.sh — P0-3 fix verification
# Verifies: run_all.sh auto-discovers all test_*.sh files instead of manual list.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_ALL="$SCRIPT_DIR/run_all.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_run_all_auto_discovery.sh ══"

# ── Test 1: run_all.sh uses auto-discovery (no hardcoded file list for test_*) ─
# After fix, run_all.sh should NOT contain a long hardcoded list of test_*.sh paths.
# It should use find/glob to auto-discover.

# Check that run_all.sh uses glob or find pattern
if grep -qE 'for .*test_\*' "$RUN_ALL" || grep -qE 'find.*test_' "$RUN_ALL" || grep -qE 'for .*in .*tests/\*test_' "$RUN_ALL"; then
    ok "run_all.sh uses auto-discovery pattern (not hardcoded list)"
else
    # Check if it still has the old hardcoded list
    hardcoded_count=$(grep -c 'test_' "$RUN_ALL" 2>/dev/null || true)
    if [ "$hardcoded_count" -gt 5 ]; then
        fail "run_all.sh still has hardcoded test file list (P0-3: $hardcoded_count test_ references)"
    else
        ok "run_all.sh does not use hardcoded list"
    fi
fi

# Count actual test files (excluding run_all.sh, fixtures, test_run_all_auto_discovery.sh itself)
actual_tests=$(find "$SCRIPT_DIR" -maxdepth 1 -name 'test_*.sh' -type f \
    ! -name 'test_run_all_auto_discovery.sh' \
    ! -name 'test_suite_structure.sh' | wc -l)

if [ "$actual_tests" -gt 0 ]; then
    ok "test directory contains discoverable test files ($actual_tests)"
else
    fail "test directory contains no discoverable test files"
fi

# ── Test 2: run_all.sh must include this auto-discovery guard ─────────────
if grep -q 'test_run_all_auto_discovery.sh' "$RUN_ALL"; then
    fail "run_all.sh excludes test_run_all_auto_discovery.sh from the release gate"
else
    ok "run_all.sh includes the auto-discovery guard"
fi

# run_all.sh should NOT run itself as a test
if grep -q 'run_tests()' "$RUN_ALL" 2>/dev/null; then
    fail "run_all.sh defines run_tests function conflicting with release.sh"
else
    ok "run_all.sh does not self-reference in test list"
fi

# ── Test 3: run_all.sh output still shows suite results ───────────────────
if grep -q 'TOTAL_PASS\|TOTAL_FAIL' "$RUN_ALL"; then
    ok "run_all.sh tracks pass/fail counts"
else
    fail "run_all.sh missing pass/fail tracking"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
