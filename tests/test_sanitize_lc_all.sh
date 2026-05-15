#!/bin/bash
# test_sanitize_lc_all.sh — RED→GREEN: grep_files in release-sanitize.sh
# must prefix grep with LC_ALL=C for locale-safe pattern matching.
# TDD P1-1
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANITIZE="$ROOT/scripts/release-sanitize.sh"
echo "=== test_sanitize_lc_all: LC_ALL=C in grep_files ==="
if grep -qF 'LC_ALL=C grep' "$SANITIZE"; then
    ok "release-sanitize.sh grep_files uses LC_ALL=C grep"
else
    fail "release-sanitize.sh grep_files missing LC_ALL=C prefix"
fi
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
