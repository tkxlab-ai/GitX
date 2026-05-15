#!/bin/bash
# run_all.sh — TKX Git Release Skill test suite entry point
# Runs all tests in the tests/ directory.
# usage: bash tests/run_all.sh
# exit:  0 all pass / 1 any fail
#
# P0-3: Auto-discovers all test_*.sh files — no hardcoded list needed.
# Exclusions: run_all.sh itself, test_suite_structure.sh (meta).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

run_test() {
    local test_script="$1"
    local name
    name=$(basename "$test_script")
    if bash "$test_script"; then
        TOTAL_PASS=$((TOTAL_PASS+1))
    else
        echo "  ⛔ $name FAILED"
        TOTAL_FAIL=$((TOTAL_FAIL+1))
    fi
    echo ""
}

echo "════════════════════════════════════════"
echo "  TKX Git Release Skill — Test Suite"
echo "════════════════════════════════════════"
echo ""

# Auto-discover all test_*.sh files (P0-3 fix)
EXCLUDE="run_all.sh|test_suite_structure.sh"
for t in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$t" ] || continue
    bn=$(basename "$t")
    if echo "$bn" | grep -qE "^($EXCLUDE)$"; then
        continue
    fi
    run_test "$t"
done

echo "════════════════════════════════════════"
echo "Suite Results: ✅$TOTAL_PASS suites passed / ❌$TOTAL_FAIL suites failed"

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "🎉 All tests GREEN"
    exit 0
else
    echo "❌ $TOTAL_FAIL test suite(s) FAILED"
    exit 1
fi
