#!/bin/bash
# test_audit_dual_source_whitelist.sh — RED→GREEN: §9 dual-source check must
# only whitelist release-* files that are root-side-only, NOT bundle-side-only.
# TDD P1-11
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ROOT/scripts/release-audit.sh"
echo "=== test_audit_dual_source_whitelist: §9 drift detection ==="
# The broad grep -v "^Only in.*scripts: release-" is the problematic pattern
if grep -qF 'grep -v "^Only in.*scripts: release-"' "$AUDIT"; then
    fail "release-audit.sh §9: overly broad whitelist still present (both sides suppressed)"
else
    ok "release-audit.sh §9: broad '*scripts: release-' whitelist removed"
fi
# The new whitelist must restrict to root-side-only (PROJECT_ROOT/scripts)
if grep -qE 'SCRIPTS_ROOT|Only in.*PROJECT_ROOT.*scripts.*release-|whitelist.*root|root.*whitelist' "$AUDIT"; then
    ok "release-audit.sh §9: whitelist restricted to root-side 'Only in' lines"
else
    fail "release-audit.sh §9: missing root-side-restricted whitelist for release- files"
fi
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
