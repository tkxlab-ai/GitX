#!/bin/bash
# test_audit_version_validation.sh — v1.0.8 hardening (Sec Minor #3).
# release.sh has a strict VERSION regex; release-audit.sh standalone did not.
# An unvalidated VERSION reaches awk/grep patterns, opening regex-injection
# and arbitrary-path surfaces. This test asserts audit applies the same
# regex as release.sh:47.
# exit: 0=all pass, 1=any fail
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT="$ROOT/scripts/release-audit.sh"
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
echo "══ test_audit_version_validation.sh ══"

# Static: regex is present in audit
if grep -qE '\^v\[0-9\]\+\\\.\[0-9\]' "$AUDIT"; then
    ok "release-audit.sh contains version regex"
else
    fail "release-audit.sh missing version regex"
fi

# Behavioral: invalid versions rejected before any side effect
test_reject() {
    local label="$1" ver="$2"
    out=$(bash "$AUDIT" "$ver" 2>&1 || true)
    if echo "$out" | grep -qiE 'invalid version|expected v'; then
        ok "$label: '$ver' rejected"
    else
        fail "$label: '$ver' NOT rejected (audit accepted invalid input)"
        echo "       output head: $(echo "$out" | head -1)"
    fi
}

test_reject "path traversal" "../../etc/passwd"
test_reject "shell metachar" "v1.0.0; rm -rf /"
test_reject "empty-suffix"   "v"
test_reject "non-v prefix"   "1.0.0"
test_reject "wildcard chars" "v1.*.0"

# Behavioral: valid version passes the regex (other audit failures are fine)
out=$(bash "$AUDIT" v99.99.99 2>&1 || true)
if echo "$out" | grep -qiE 'invalid version'; then
    fail "valid 'v99.99.99' rejected as invalid"
else
    ok "valid 'v99.99.99' passes version regex (audit may fail elsewhere — that's OK)"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
