#!/bin/bash
# run_all.sh — TKX Git Release Skill test suite entry point
# Runs all tests in the tests/ directory.
# usage: bash tests/run_all.sh
# exit:  0 all pass / 1 any fail
#
# P0-3: Auto-discovers all test_*.sh files — no hardcoded list needed.
# Exclusions: run_all.sh itself, test_suite_structure.sh (meta).
#
# Hermetic: each suite runs under `env -i` with a fixed allowlist, so a
# variable exported by the caller (PROJECT_ROOT, SKILL_NAME, ...) cannot turn
# a suite green or red, and with its own TMPDIR, so suites never share or
# collide on scratch paths.
# Self-checking: exit 0 alone is not trusted. A suite is green only if it
# exits 0 AND prints a summary line that reports 0 failed and >0 passed (or
# >0 skipped). Red runs keep their logs and TMPDIRs for inspection.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
EXCLUDE="run_all.sh|test_suite_structure.sh"
SUMMARY_RE='(✅ *[0-9]+.*❌ *[0-9]+)|([0-9]+ passed,? */? *[0-9]+ failed)|(^PASS [0-9]+ / [0-9]+)'
RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gitx-tests.XXXXXX")
# A relative TMPDIR would follow every suite that changes directory; pin it.
RUN_TMP=$(cd "$RUN_TMP" && pwd)

# Sets SUMMARY PASSED FAILED SKIPPED from a suite log. Counts come from the
# ERE-matched region only, so digits elsewhere on the line (a version, an
# "E2E" prefix) are never read as counts.
parse_summary() {
    local log="$1" nums
    # -a: GNU grep reports "binary file matches" for a log with NUL/invalid
    # UTF-8 bytes instead of printing the summary line
    SUMMARY=$(grep -aE "$SUMMARY_RE" "$log" | tail -1 || true)
    PASSED=0; FAILED=0; SKIPPED=0
    [ -n "$SUMMARY" ] || return 0
    nums=$(grep -oE "$SUMMARY_RE" <<<"$SUMMARY" | head -1 | grep -oE '[0-9]+' | tr '\n' ' ' || true)
    # shellcheck disable=SC2086
    set -- $nums
    PASSED=${1:-0}; FAILED=${2:-0}
    # "PASS N / M" reports passed and total, not failed
    case "$SUMMARY" in PASS\ [0-9]*) FAILED=$((FAILED - PASSED)) ;; esac
    SKIPPED=$(grep -oE '(➖ *[0-9]+|[0-9]+ skipped)' <<<"$SUMMARY" | grep -oE '[0-9]+' | head -1 || true)
    SKIPPED=${SKIPPED:-0}
}

run_test() {
    local test_script="$1" name log suite_tmp rc start reason
    name=$(basename "$test_script")
    log="$RUN_TMP/$name.log"
    suite_tmp=$(mktemp -d "$RUN_TMP/${name%.sh}.XXXXXX")
    start=$SECONDS
    # set +e + PIPESTATUS: under set -e the tee pipeline would otherwise mask
    # (or abort on) the suite's own exit code.
    # tee waits for EOF: a suite that leaves a background child holding stdout
    # open would hang the runner here — suites must reap or redirect children.
    set +e
    env -i PATH="$PATH" HOME="$HOME" TMPDIR="$suite_tmp" LANG="${LANG:-}" LC_ALL="${LC_ALL:-}" \
        LC_CTYPE="${LC_CTYPE:-}" TERM="${TERM:-dumb}" USER="${USER:-}" SHELL="${SHELL:-/bin/bash}" \
        CI="${CI:-}" bash "$test_script" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    set -e
    parse_summary "$log"
    reason=""
    if   [ "$rc" -ne 0 ];        then reason="rc=$rc"
    elif [ -z "$SUMMARY" ];      then reason="no summary line — silent abort?"
    elif [ "$FAILED" -gt 0 ];    then reason="summary reports $FAILED failed but exit 0"
    elif [ "$PASSED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then reason="vacuous: 0 assertions"
    fi
    if [ -z "$reason" ]; then
        rm -rf "$suite_tmp" "$log"
        echo "  ✅ $name — $PASSED passed ($((SECONDS-start))s)"
        TOTAL_PASS=$((TOTAL_PASS+1))
    else
        echo "  ⛔ $name FAILED ($reason) → log: $log"
        TOTAL_FAIL=$((TOTAL_FAIL+1))
    fi
    echo ""
}

echo "════════════════════════════════════════"
echo "  TKX Git Release Skill — Test Suite"
echo "════════════════════════════════════════"
echo ""

# Auto-discover all test_*.sh files (P0-3 fix)
for t in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$t" ] || continue
    bn=$(basename "$t")
    if grep -qE "^($EXCLUDE)$" <<<"$bn"; then
        continue
    fi
    run_test "$t"
done

if [ "$TOTAL_FAIL" -eq 0 ]; then
    rm -rf "$RUN_TMP"
else
    echo "   kept for inspection: $RUN_TMP"
    echo ""
fi
echo "════════════════════════════════════════"
echo "Suite Results: ✅$TOTAL_PASS suites passed / ❌$TOTAL_FAIL suites failed"

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "🎉 All tests GREEN"
    exit 0
else
    echo "❌ $TOTAL_FAIL test suite(s) FAILED"
    exit 1
fi
