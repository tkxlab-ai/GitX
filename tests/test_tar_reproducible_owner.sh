#!/bin/bash
# test_tar_reproducible_owner.sh — RED→GREEN: release.sh tar command must use
# --owner=0 --group=0 --numeric-owner for reproducible ownership across builds.
# TDD P1-3
set -euo pipefail
PASS=0; FAIL=0
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_SH="$ROOT/scripts/release.sh"
echo "=== test_tar_reproducible_owner: tar ownership flags ==="
if grep -qF -- '--owner=0' "$RELEASE_SH" && grep -qF -- '--group=0' "$RELEASE_SH"; then
    ok "release.sh: tar uses --owner=0 --group=0 for reproducible ownership"
else
    fail "release.sh: tar missing --owner=0 --group=0 (ownership non-reproducible)"
fi
if grep -qF -- '--numeric-owner' "$RELEASE_SH"; then
    ok "release.sh: tar uses --numeric-owner"
else
    fail "release.sh: tar missing --numeric-owner"
fi
echo ""
echo "Results: ✅$PASS passed / ❌$FAIL failed"
[ "$FAIL" -eq 0 ] && echo "PASS" && exit 0
echo "FAIL"; exit 1
