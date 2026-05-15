#!/bin/bash
# test_audit_mktemp_safe.sh — RED→GREEN: release-audit.sh must not use
# predictable /tmp paths; must delegate temp creation to mktemp(1).
# TDD P0-4: /tmp/.audit-tarlist-$$ → mktemp
set -euo pipefail

PASS=0; FAIL=0

check() {
    local label="$1"; shift
    if "$@" 2>/dev/null; then
        echo "  ✅ $label"; PASS=$((PASS+1))
    else
        echo "  ❌ $label"; FAIL=$((FAIL+1))
    fi
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUDIT="$ROOT/scripts/release-audit.sh"

echo "=== test_audit_mktemp_safe: predictable temp path guard ==="

# No hard-coded /tmp/ assignment for the tarlist variable
check "release-audit.sh: no LIST=/tmp/ hard-coded path" \
    bash -c '! grep -qE "LIST=/tmp/" '"\"$AUDIT\""

# Must use mktemp at least once for the tarlist (already uses mktemp for _SEC_LOG)
check "release-audit.sh: LIST assigned via mktemp" \
    grep -qF 'LIST=$(mktemp)' "$AUDIT"

if [ "$FAIL" -gt 0 ]; then
    echo "FAIL $FAIL / $((PASS+FAIL))"
    exit 1
fi
echo "PASS $PASS / $((PASS+FAIL))"
