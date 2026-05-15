#!/bin/bash
# test_touch_error_visibility.sh — RED→GREEN: touch -t in release.sh must not
# silently swallow errors via 2>/dev/null; errors must surface to stderr.
# TDD P1-2
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
echo "=== test_touch_error_visibility: touch stderr not suppressed ==="
# The touch line must NOT have 2>/dev/null
# After fix: keep || true for robustness, but remove 2>/dev/null so errors surface
if grep -qF 'exec touch' "$RELEASE_SH" && \
   ! grep -F 'exec touch' "$RELEASE_SH" | grep -qF '2>/dev/null'; then
    ok "release.sh: touch -t errors not silently suppressed (no 2>/dev/null)"
else
    fail "release.sh: touch -t errors silently suppressed with 2>/dev/null"
fi
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
