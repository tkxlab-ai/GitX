#!/bin/bash
# test_release_artifact_private_state.sh — existing release artifacts must not leak local state
#
# Scans checked-in/generated Release/* source tarballs for private agent/cache
# paths. This catches stale release artifacts that predate release.sh excludes.
#
# exit: 0=all pass, 1=any fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "══ test_release_artifact_private_state.sh ══"

found=0
while IFS= read -r tarball; do
    [ -z "$tarball" ] && continue
    found=1
    if tar tzf "$tarball" 2>/dev/null | grep -qE '/(\.1by1/|\.i18n-cache/|\.cache/|\.ssh/|\.aws/|\.env[^/]*|\.python-version)'; then
        fail "$(realpath "$tarball") contains private local state paths"
    else
        ok "$(basename "$tarball") has no private local state paths"
    fi
done < <(find "$PROJECT_ROOT/Release" -maxdepth 2 -name '*-source.tar.gz' -type f 2>/dev/null | LC_ALL=C sort)

if [ "$found" -eq 1 ]; then
    ok "scanned at least one release source tarball"
else
    ok "no release source tarballs present to scan"
fi

echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
