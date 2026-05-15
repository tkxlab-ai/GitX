#!/bin/bash
# test_audit_tempfile_trap.sh — RED→GREEN:
# release-audit.sh must trap _SEC_LOG for cleanup on early exit.
# TDD P1-CR3-2
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT_SH="$ROOT/scripts/release-audit.sh"

echo "=== test_audit_tempfile_trap: temp file cleanup ==="

# Test 1: _SEC_LOG must be cleaned up by a trap (not only at end-of-script rm)
# Extract the 15 lines around the _SEC_LOG=$(mktemp) line to see if trap follows
_SEC_LINE=$(grep -n '_SEC_LOG=\$(mktemp)' "$AUDIT_SH" | head -1 | cut -d: -f1)
_EARLY=$(sed -n "${_SEC_LINE},$((${_SEC_LINE}+12))p" "$AUDIT_SH")
if echo "$_EARLY" | grep -qE 'trap.*_SEC_LOG|trap.*EXIT'; then
    ok "release-audit.sh: _SEC_LOG protected by trap on early exit"
else
    fail "release-audit.sh: _SEC_LOG has no trap — leaks on early exit (exit 2 path)"
fi

# Test 2: LIST temp file inside audit_section_5_tarball must have local cleanup
_LIST_LINE=$(grep -n 'LIST=\$(mktemp)' "$AUDIT_SH" | head -1 | cut -d: -f1)
_LIST_BLOCK=$(sed -n "${_LIST_LINE},$((${_LIST_LINE}+3))p" "$AUDIT_SH")
if echo "$_LIST_BLOCK" | grep -qE 'trap.*LIST|trap.*RETURN'; then
    ok "release-audit.sh: LIST temp file in §5 has trap RETURN guard"
else
    fail "release-audit.sh: LIST in audit_section_5_tarball() has no trap — leaks on tar failure"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
