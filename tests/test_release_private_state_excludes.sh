#!/bin/bash
# test_release_private_state_excludes.sh — prevent local agent/cache state from shipping
#
# Verifies:
#   1. release.sh excludes private/local state directories from source staging.
#   2. release-audit.sh rejects source tarballs containing those paths.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
AUDIT_SH="$PROJECT_ROOT/scripts/release-audit.sh"

PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_private_state_excludes.sh ══"

# ── Test 1: release.sh excludes local AI/session/cache dotdirs ───────────
for pat in ".omc" ".1by1" ".i18n-cache" ".cache" ".env*" ".ssh" ".aws"; do
    if grep -Fq -- "--exclude='$pat'" "$RELEASE_SH" || grep -Fq -- "--exclude=\"$pat\"" "$RELEASE_SH"; then
        ok "release.sh excludes $pat"
    else
        fail "release.sh does not exclude $pat from source tarball staging"
    fi
done

# ── Test 2: audit rejects these paths if they appear in tarball list ─────
if grep -qE '不含.*(\.1by1|i18n-cache|private local state|hidden state)' "$AUDIT_SH"; then
    ok "release-audit.sh checks for private/local state paths"
else
    fail "release-audit.sh does not reject private/local state paths in tarball"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
