#!/bin/bash
# test_dual_source_check_release.sh — RED→GREEN:
# check_dual_source() in release.sh must use SCRIPTS_ROOT-pinned case filter,
# not a broad grep -v that allows bundle-side release-* drift to pass silently.
# TDD P1-CR3-1
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"

echo "=== test_dual_source_check_release: check_dual_source() whitelist ==="

# Test 1: broad pattern must NOT be present in check_dual_source block
# The broad pattern '| grep -v "^Only in.*scripts: release-"' allows
# bundle-side extras (e.g. skills/x/scripts/release-rogue.sh) to pass silently.
_BLOCK=$(sed -n '/check_dual_source()/,/^}/p' "$RELEASE_SH" | head -50)
if echo "$_BLOCK" | grep -qE 'grep -v.*".*Only in.*scripts: release-"'; then
    fail "check_dual_source(): still uses broad grep -v pattern (allows bundle-side drift)"
else
    ok "check_dual_source(): no broad grep -v pattern"
fi

# Test 2: case-based SCRIPTS_ROOT filter must be present (matches audit §9 approach)
if echo "$_BLOCK" | grep -qE 'SCRIPTS_ROOT|case.*Only in'; then
    ok "check_dual_source(): uses SCRIPTS_ROOT-pinned case filter"
else
    fail "check_dual_source(): missing SCRIPTS_ROOT-pinned case filter"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
